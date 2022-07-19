#!/bin/bash

# Generate Polarion repors and upload
# Polarion testcases and testruns will be generated

function source_and_verify_polarion_params() {
    INFO "Polarion: Report to Polarion selected. Verify provided params"

    if [[ -n "$POLARION_VARS_FILE" && -s "$POLARION_VARS_FILE" ]]; then
        INFO "Polarion: Variable file detected. Importing..."
        # shellcheck disable=SC1090
        source "$POLARION_VARS_FILE"
    fi

    if [[ -z "$POLARION_SERVER" ||
          -z "$POLARION_USER" ||
          -z "$POLARION_PASS" ||
          -z "$POLARION_PROJECT_ID" ||
          -z "$POLARION_TEAM_NAME" ||
          -z "$POLARION_COMPONENT_ID" ||
          -z "$POLARION_TESTRUN_TEMPLATE" ]]; then
        ERROR "Polarion: Missing some of the required variables. Unable to proceed"
    else
        INFO "Polarion: Required variables validated"
    fi
}

function report_polarion() {
    INFO "Polarion: Report Polarion test state (internal only)"
    local polarion_auth
    local polarion_auth_file="/tmp/polarion_auth"

    mkdir -p "$POLARION_REPORTS"
    polarion_auth=$(echo "${POLARION_USER}:${POLARION_PASS}" | base64 -w 0)
    echo "--header \"Authorization: Basic ${polarion_auth}\"" > "$polarion_auth_file"

    for junit in "$TESTS_LOGS"/*.xml; do
        if [[ -s "$junit" && "$junit" =~ "junit" ]]; then
            generate_polarion_testplan_id "$junit"

            INFO "Polarion: The following junit file has been found - $junit"
            generate_polarion_testcases "https://$POLARION_SERVER/polarion" \
                "$polarion_auth_file" "$junit" "$POLARION_PROJECT_ID" \
                "$POLARION_TEAM_NAME" "$POLARION_USER" "$POLARION_COMPONENT_ID" \
                "$POLARION_TESTPLAN_ID" "$POLARION_TESTCASES_DOC"

            generate_polarion_testrun "https://$POLARION_SERVER/polarion" \
                "$polarion_auth_file" "$junit" "$POLARION_PROJECT_ID" \
                "$POLARION_TEAM_NAME" "$POLARION_TESTRUN_TEMPLATE" \
                "$POLARION_TESTPLAN_ID"
        else
            ERROR "Polarion: Unable to generate polarion report file. The junit file is missing
            Expect to find a junit file with 'junit' as part of the name in it."
        fi
    done
    rm -f "$polarion_auth_file"
}

function generate_polarion_testplan_id() {
    INFO "Polarion: Generate Polarion TestPlan ID"
    local junit_xml="$1"
    local junit_name
    local acm_ver
    local subm_ver

    junit_name=$(fetch_polarion_test_name_from_file "$junit_xml")
    acm_ver=$(echo "$junit_name" | grep -Po '(?<=ACM-)[[0-9].[0-9].[0-9]]*' | tr "." "_" || :)
    subm_ver=$(echo "$junit_name" | grep -Po '(?<=Submariner-)[[0-9].[0-9][0-9].[0-9]]*' | tr "." "_" || :)

    if [[ -z "$acm_ver" || -z "$subm_ver" ]]; then
        ERROR "Polarion: Unable to generate TestPlan ID. Missing ACM or Submariner version vars"
    fi

    export POLARION_TESTPLAN_ID="Submariner_${subm_ver}_in_ACM_${acm_ver}"
    export POLARION_TESTCASES_DOC="${POLARION_TESTPLAN_ID}_Testscases"
}

function generate_polarion_testcases() {
    local polarion_url="$1"
    local polarion_auth="$2" # Includes Polarion 'user:password' | base64 --wrap 0
    local junit_xml="$3"
    local polarion_project_id="$4"
    local polarion_team_name="$5"
    local polarion_user_name="$6"
    local polarion_component_id="$7"
    local polarion_test_plan_id="$8"
    local polarion_testcases_doc="$9"

    local testsuite_name
    local polarion_testcases_xml
    local testcases_list
    local current_script

    current_script="$(hostname) : $(realpath -s "${BASH_SOURCE[$i+1]}")"

    INFO "Polarion: Generate Polarion testcases from $junit_xml file"
    testsuite_name=$(fetch_polarion_test_name_from_file "$junit_xml")
    polarion_testcases_xml="$POLARION_REPORTS/${testsuite_name}_polarion_testcases.xml"

    INFO "Polarion: Fetch the list of Test-Cases in format - 'class-name.test-name'"
    testcases_list=$(grep '<testcase ' "$junit_xml" \
        | sed -r 's/.*name="([^"]+).*classname="([^"]+).*/\2.\1/ ; s/[0-9]+ : //')

    INFO "Polarion: Initialize the $polarion_testcases_xml testcases xml file"
    echo -e "<?xml version=\"1.0\" encoding=\"UTF-8\"?>  \n\
    <testcases project-id=\"${polarion_project_id}\" document-relative-path=\"${polarion_team_name}/${polarion_testcases_doc}\">  \n\
      <properties>  \n\
          <property name=\"lookup-method\" value=\"name\"/>  \n\
      </properties>" > "$polarion_testcases_xml"

    INFO "Polarion: Injecting custom-fields for each test-case, into $polarion_testcases_xml"
    echo "$testcases_list" | while read -r testcase_name; do
        local test_name="${testcase_name#*.}" # text after the dot

        echo "<testcase approver-ids=\"${polarion_user_name}:approved\" status-id=\"approved\" assignee-id=\"${polarion_user_name}\">
            <title>${testsuite_name}.${test_name}</title>
            <description>
              &lt;span style=\"font-size: 12pt; font-weight: bold;\"&gt; ${testsuite_name}.${test_name} &lt;/span&gt;
              &lt;ul&gt;
            </description>
                " >> "$polarion_testcases_xml"

        echo "
        <custom-fields>
            <custom-field id=\"casecomponent\" content=\"${polarion_component_id}\" />
            <custom-field id=\"testtype\" content=\"functional\" />
            <custom-field id=\"caseimportance\" content=\"medium\" />
            <custom-field id=\"caselevel\" content=\"system\" />
            <custom-field id=\"caseposneg\" content=\"positive\" />
            <custom-field id=\"legacytest\" content=\"true\" />
            <custom-field id=\"caseautomation\" content=\"automated\" />
            <custom-field id=\"tcmsplan\" content=\"${polarion_test_plan_id}\" />
            <custom-field id=\"automation_script\">
                \"${current_script}\"
            </custom-field>
        </custom-fields>
        </testcase>
        " >> "$polarion_testcases_xml"
    done
    echo "</testcases>" >> "$polarion_testcases_xml"

    push_update_to_polarion "$polarion_url" "$polarion_auth" \
        "testcase" "$polarion_testcases_xml"
}

function generate_polarion_testrun() {
    local polarion_url="$1"
    local polarion_auth="$2" # Includes Polarion 'user:password' | base64 --wrap 0
    local junit_xml="$3"
    local polarion_project_id="$4"
    local polarion_team_name="$5"
    local polarion_testrun_template="$6"
    # Optional: To set test plan (instead of the test plan from the testrun template)
    local polarion_testplan_id="$7"

    local testsuite_name
    # If "true", display Junit skipped test as "Waiting" in Polarion (i.e. test not run yet)
    local polarion_include_skipped="false"
    local polarion_testrun_xml
    local polarion_testrun_id
    local polarion_suite_content

    INFO "Polarion: Generate Polarion testruns from $junit_xml file"
    testsuite_name=$(fetch_polarion_test_name_from_file "$junit_xml")
    polarion_testrun_xml="$POLARION_REPORTS/${testsuite_name}_polarion_testrun.xml"

    # Set Polarion test-run ID with plain text only, and lowercase
    polarion_testrun_id="${polarion_team_name//[^a-zA-Z0-9]/-}_${testsuite_name//[^a-zA-Z0-9]/-}"
    polarion_testrun_id="${polarion_testrun_id,,*}"

    INFO "Polarion: Generating Test-run file [$polarion_testrun_xml] to import:
    Polarion Test Run ID: $polarion_testrun_id
    Polarion Project: $polarion_project_id
    Polarion Team: $polarion_team_name
    Polarion Test Suite: $testsuite_name
    Polarion Test Plan ID: $polarion_testplan_id
    Polarion Test Run Template: $polarion_testrun_template
    Include Skipped Tests: $polarion_include_skipped"

    cp "$junit_xml" "$polarion_testrun_xml"
    
    if [[ "$POLARION_ADD_SKIPPED" == "true" ]]; then
        polarion_include_skipped="true"
    fi

    INFO "Polarion: Define Polarion <testsuite> properties"
    polarion_suite_content="<testsuites> \n\
        <properties> \n\
            <property name=\"polarion-testrun-id\" value=\"${polarion_testrun_id}\" /> \n\
            <property name=\"polarion-testrun-title\" value=\"$testsuite_name\" /> \n\
            <property name=\"polarion-testrun-template-id\" value=\"$polarion_testrun_template\" /> \n\
            <property name=\"polarion-project-id\" value=\"$polarion_project_id\" /> \n\
            <property name=\"polarion-response-myteamsname\" value=\"$polarion_team_name\" /> \n\
            <property name=\"polarion-lookup-method\" value=\"name\" /> \n\
            ${polarion_testplan_id:+<property name=\"polarion-custom-plannedin\" value=\"$polarion_testplan_id\" />} \n\
            <property name=\"polarion-include-skipped\" value=\"${polarion_include_skipped}\" /> \n\
            <property name=\"polarion-create-defects\" value=\"true\" /> \n\
            <property name=\"polarion-testrun-status-id\" value=\"inprogress\" /> \n\
        </properties> \n\
    <testsuite "

    # Insert the "polarion_suite_content" into the generated file
    sed_expression="0,/<testsuite /s,<testsuite ,$polarion_suite_content,"
    sed -r "$sed_expression" -i "$polarion_testrun_xml"

    # Add </testsuiteS> tag, after the last </testsuite> tag:
    sed -r -z 's:(.*</testsuite>):\1\n</testsuites>:' -i "$polarion_testrun_xml"

    # Add plain text into each Test Case Verdict in $polarion_testrun_xml (add 'polarion-testcase-comment'):"
    # Define property of <testcase> comment in the test-run xml
    local testrun_comment="Auto generated ${BUILD_URL:+in Jenkins Build $BUILD_URL }from Junit file: $junit_xml"
    local testcase_properties="\n\
        <properties> \n\
            <property name=\"polarion-testcase-comment\" value=\"${testrun_comment}\" /> \n\
        </properties> \n\
    </testcase>"
    sed_expression="s%</testcase>%${testcase_properties//%/\\%}%g"
    # Insert the property instead of EACH testcase tag
    sed -r "$sed_expression" -i "$polarion_testrun_xml"

    # Add escaped HTML <br> tags at the end of all textual lines in $polarion_testrun_xml"
    local temp_testrun
    temp_testrun="$(mktemp)_testrun"
    awk '!/<|>|^\s*$/{$0=$0"&#xD;&#xA;&#13;"}1' "$polarion_testrun_xml" > "${temp_testrun}"
    mv "${temp_testrun}" "$polarion_testrun_xml"

    INFO "Polarion: Update <testsuite name> and <classname> to: $testsuite_name"
    sed -r "s/(testsuite name=\")([^\"]+)/\1${testsuite_name}/" -i "$polarion_testrun_xml"
    sed -r "s/(classname=\")([^\"]+)/\1${testsuite_name}/" -i "$polarion_testrun_xml"

    push_update_to_polarion "$polarion_url" "$polarion_auth" \
        "xunit" "$polarion_testrun_xml"
}

function fetch_polarion_test_name_from_file() {
    local junit_file_path="$1"
    local test_name
    test_name="$(basename "${junit_file_path%.*}")"
    test_name="${test_name//_*junit/}"
    echo "$test_name"
}

# Upload report to Polarion.
# SUpports "xunit" or "testcase" types
function push_update_to_polarion() {
    local polarion_url="$1"
    local polarion_auth_file="$2" # Includes Polarion 'user:password' | base64 --wrap 0
    local polarion_import_type="$3" # "xunit" or "testcase"
    local polarion_import_file="$4" # Filepath to import

    local polarion_log="$POLARION_REPORTS/polarion_${polarion_import_type}.log"
    local polarion_job_id
    local timeout
    local testrun_url
    local wait_timeout=20
    local report_state="false"

    INFO "Polarion: Push update to Polarion - type: $polarion_import_type, file: $polarion_import_file"
    curl --config "$polarion_auth_file" -s -k -X POST -F file=@"${polarion_import_file}" \
        "${polarion_url}/import/${polarion_import_type}" > "$polarion_log"
    polarion_job_id=$(awk '/job-ids/ { print $4 }' "$polarion_log")

    if [[ -z "$polarion_job_id" ]] || [[ "$polarion_job_id" == 0 ]] ; then
        WARNING "Polarion: Error in the file or data to import to Polarion: $polarion_import_file"
    fi

    local polarion_job_url="${polarion_url}/import/${polarion_import_type}-log?jobId=${polarion_job_id}"
    INFO "Polarion: Checking $polarion_import_type import job status at: $polarion_job_url"

    # Generation of the report may take time. Retry a number of times to fetch the report.
    timeout=0
    until [[ "$timeout" -eq "$wait_timeout" ]]; do
        INFO "Polarion: Waiting for the $polarion_import_type report to be created..."
        curl --config "$polarion_auth_file" -s -k "$polarion_job_url" \
            | sed -r 's/&#034;|&#039;/\"/g' > "$polarion_log"

        if grep 'Import.*Message sent' "$polarion_log"; then
            INFO "Polarion: The $polarion_import_type report has been created"
            report_state="true"
            break
        fi
        sleep $(( timeout++ ))
    done
    if [[ "$report_state" == "false" ]]; then
        ERROR "Polarion: Creation of the report failed"
    fi

    if tail -n 10 "$polarion_log" | grep "failed" ; then
        ERROR "Polarion: Importing $polarion_import_type to Polarion did not complete successfully"
    fi

    if [[ "$polarion_import_type" == "xunit" ]]; then
        testrun_url=$(grep 'testrun-url' "$polarion_log" | awk '{print $3}')
        INFO "Polarion: The TestRun url - $testrun_url"
    fi
    INFO "Polarion: Execution finished"
}

#!/usr/bin/env python3

import json
import html
import os
import re
import requests
import shutil
import xml.etree.ElementTree as ET

from argparse import ArgumentParser
from configparser import ConfigParser
from configparser import NoOptionError
from pathlib import Path
from requests.auth import HTTPBasicAuth
from time import sleep


LOGS_DIR = os.getenv('POLARION_REPORTS', "")


def parse_args():
    parser = ArgumentParser()
    parser.add_argument('--config', help='Path to config file with Polarion'
                                         'auth and components details',
                        required=True)
    parser.add_argument('--path', help='The path to junit xml files',
                        required=True)
    parser.add_argument('--prefix', help='Prefix for filtering the xml files',
                        required=False)
    return parser.parse_args()


def locate_xml_files(path, prefix):
    """Locate xml report files from a given path."""
    search_str = f"**/*{prefix}*junit.xml" if prefix else "**/*junit.xml"
    return list(Path(path).glob(search_str))


def validate_config_file(path):
    """Validate polarion config file.

    [polarion_auth]
    server = https://<polarion_server_url>/polarion
    user = <username>
    pass = <password>

    [polarion_team_config]
    project_id = <project name>
    component_id = <component name>
    team_name = <team name>
    testrun_template = <testrun template name>
    """
    if not Path(path).exists():
        raise FileNotFoundError("Polarion: Polarion config file is missing")

    config = ConfigParser()
    config.read(path)
    data = {'polarion_auth': ['server', 'user', 'pass'],
            'polarion_team_config': ['project_id', 'component_id', 'team_name',
                                     'testrun_template']}
    polarion_config = {}
    for section, params in data.items():
        for param in params:
            try:
                value = config.get(section, param)
                polarion_config[param] = value
            except NoOptionError:
                print(f"Polarion: Key is missing in config file: {param}")

    return polarion_config


def write_logs_into_file(log, path):
    """Write log output into the log file."""
    with open(path, "w") as file:
        file.write(html.unescape(log))


class PolarionProcessReports:
    """The class generates and report testcase and testplan reports."""

    def __init__(self, polarion_config, reports_path, reports_prefix):
        self.polation_config = validate_config_file(polarion_config)
        self.path = reports_path
        self.prefix = reports_prefix
        self.junit_files_dir = locate_xml_files(self.path, self.prefix)
        self.junit_file = None
        self.polarion_test_name = None
        self.polarion_test_plan_id = None
        self.polarion_test_case_doc = None

    def fetch_polarion_testname(self, junit_path):
        """Fetch the polarion test name out of junit file."""
        file_name = Path(junit_path).stem
        polarion_test_name = file_name.split('_')[0]
        return polarion_test_name

    def generate_polarion_testplan_id_and_testcase_doc(self, test_name):
        """Generate testplan id and testcase doc out of test name."""
        acm_ver = re.search(r'(?<=ACM-)[0-9]+(?:\.[0-9]+){2}', test_name)
        acm_ver = acm_ver.group().replace('.', '_')
        subm_ver = re.search(r'(?<=Submariner-)[0-9]+(?:\.[0-9]+){2}', test_name)
        subm_ver = subm_ver.group().replace('.', '_')

        test_plan_id = f"Submariner_{subm_ver}_in_ACM_{acm_ver}"
        test_case_id = f"{test_plan_id}_Testscases"

        return test_plan_id, test_case_id

    def fetch_tests_status(self, xml_tree):
        """Fetch tests summary (success, failed, errors)."""
        required_keys = ('tests', 'failures', 'errors')
        keys_founds = False

        for status in xml_tree.iter('testsuite'):
            state = status.attrib

            if all(key in state for key in required_keys):
                keys_founds = True
                break

        if not keys_founds:
            for status in xml_tree.iter('testsuites'):
                state = status.attrib

                if all(key in state for key in required_keys):
                    keys_founds = True
                    break

        if not keys_founds:
            raise KeyError(f"Polarion: Keys are missing - {required_keys}")

        return ET.Element("testsuite", name=self.polarion_test_name,
                          tests=state["tests"], failures=state["failures"],
                          errors=state["errors"])

    def generate_metadata(self, metadata_type):
        """Generate metadata for the testcases and testrun reports."""
        script_path = str(Path(__file__).absolute())
        if metadata_type == "testcase":
            metadata_info = [
                {"id": "tcmsplan", "content": self.polarion_test_name},
                {"id": "casecomponent", "content": "mcn"},
                {"id": "testtype", "content": "functional"},
                {"id": "caseimportance", "content": "medium"},
                {"id": "caselevel", "content": "system"},
                {"id": "caseposneg", "content": "positive"},
                {"id": "legacytest", "content": "true"},
                {"id": "caseautomation", "content": "automated"},
                {"id": "automation_script", "content": script_path},
            ]

            metadata = ET.Element("custom-fields")
            for meta_item in metadata_info:
                meta = ET.Element("custom-field", id=meta_item["id"],
                                  content=meta_item["content"])
                metadata.append(meta)
        elif metadata_type == "testrun":
            testrun_id = f"{self.polation_config['team_name'].lower()}_{self.polarion_test_name.lower()}"
            testrun_id = testrun_id.replace(".", "-")
            metadata_info = [
                {"name": "polarion-project-id",
                 "value": self.polation_config['project_id']},
                {"name": "polarion-response-myteamsname",
                 "value": self.polation_config['team_name']},
                {"name": "polarion-testrun-title",
                 "value": self.polarion_test_name},
                {"name": "polarion-custom-plannedin",
                 "value": self.polarion_test_plan_id},
                {"name": "polarion-testrun-id", "value": testrun_id},
                {"name": "polarion-testrun-template-id",
                 "value": self.polation_config['testrun_template']},
                {"name": "polarion-lookup-method", "value": "name"},
                {"name": "polarion-create-defects", "value": "true"},
                {"name": "polarion-testrun-status-id", "value": "inprogress"},
                {"name": "polarion-include-skipped", "value": "false"}
            ]

            metadata = ET.Element("properties")
            for meta_item in metadata_info:
                meta = ET.Element("property", name=meta_item["name"],
                                  value=meta_item["value"])
                metadata.append(meta)
        else:
            raise ValueError("Polarion: Metadata function should get "
                             "testcase of testrun params")

        return metadata

    def generate_testcases_report(self, xml_tree):
        """Generate Polarion testcase report and write it to a file."""
        report_name = f"{self.polarion_test_name}_polarion_testcases.xml"
        report_path = f"{LOGS_DIR}/{report_name}" \
            if LOGS_DIR else f"{report_name}"

        report = ET.Element("testcases",
                            {"project-id": self.polation_config['project_id'],
                             "document-relative-path":
                                 f"{self.polation_config['team_name']}/"
                                 f"{self.polarion_test_plan_id}_Testscases"})
        properties = ET.Element("properties")
        property = ET.Element("property", name="lookup-method", value="name")
        properties.append(property)
        report.append(properties)

        for case in xml_tree.iter('testcase'):
            name = case.get('name')
            testcase = ET.Element("testcase",
                                  {"status-id": "approved",
                                   "approver-ids": "rhel8_machine:approved",
                                   "assignee-id": "rhel8_machine"})
            title = ET.SubElement(testcase, "title")
            title.text = f"{self.polarion_test_name}.{name}"

            description = ET.SubElement(testcase, "description")
            description.text = f"{self.polarion_test_name}.{name}"

            testcase.append(self.generate_metadata("testcase"))
            report.append(testcase)

        self.write_report_into_file(report, report_path)

        return report_path

    def generate_testrun_report(self, xml_tree):
        """Generate Polarion testrun report and write it to a file."""
        report_name = f"{self.polarion_test_name}_polarion_testrun.xml"
        report_path = f"{LOGS_DIR}/{report_name}" \
            if LOGS_DIR else f"{report_name}"

        report = ET.Element("testsuites")
        report.append(self.generate_metadata("testrun"))
        testsuite = self.fetch_tests_status(xml_tree)
        report.append(testsuite)

        for case in xml_tree.iter("testcase"):
            name = case.get("name")
            time = case.get("time")
            testcase = ET.Element("testcase", name=name,
                                  classname=self.polarion_test_name, time=time)

            properties = ET.Element("properties")
            property = ET.Element("property", name="polarion-testcase-comment",
                                  value=f"Auto generated in Jenkins Build, "
                                  f"from Junit file {self.junit_file}")
            properties.append(property)
            testcase.append(properties)

            skip_state = case.find("skipped")
            if skip_state is not None:
                if skip_state.text is not None:
                    skip = skip_state.text.split("\n")[1]
                else:
                    skip = "Skip the test as not selected in test execution"

                skipped = ET.SubElement(testcase, "skipped")
                skipped.text = skip

            testsuite.append(testcase)

        self.write_report_into_file(report, report_path)

        return report_path

    def write_report_into_file(self, report, report_name):
        """Write report to an xml file."""
        tree = ET.ElementTree(report)
        ET.indent(tree, space="  ", level=0)
        tree.write(report_name, encoding="utf-8", xml_declaration=True)

    def process_reports(self):
        """Generate and publish Polarion reports."""
        polarion = PolarionPushReports(self.polation_config)

        if LOGS_DIR:
            shutil.rmtree(LOGS_DIR, ignore_errors=True)
            logs_path = Path(LOGS_DIR)
            logs_path.mkdir(exist_ok=True)

        for junit in self.junit_files_dir:
            print(f"Polarion: Processing report: {junit}")

            self.junit_file = junit
            self.polarion_test_name = self.fetch_polarion_testname(junit)
            self.polarion_test_plan_id, self.polarion_test_case_doc = \
                self.generate_polarion_testplan_id_and_testcase_doc(
                    self.polarion_test_name)
            report_root = ET.parse(junit).getroot()

            testcases_report = self.generate_testcases_report(report_root)
            testrun_report = self.generate_testrun_report(report_root)

            polarion.test_name = self.polarion_test_name

            job_id = polarion.push_report("testcase", testcases_report)
            polarion.query_report_status("testcase", job_id)

            job_id = polarion.push_report("xunit", testrun_report)
            polarion.query_report_status("xunit", job_id)

        print("Polarion: Reports processing finished")


class PolarionPushReports:
    def __init__(self, polarion_config):
        self.polation_config = polarion_config
        self.test_name = None

    def push_report(self, report_type, report):
        """Push given report to Polarion."""
        print(f"Polarion: Push update to Polarion - type: {report_type}, file: {report}")

        job_url = f"{self.polation_config['server']}/import/{report_type}"
        files = {'file': open(report, 'rb')}

        log_path = f"{LOGS_DIR}/{self.test_name}_polarion_{report_type}.log" \
            if LOGS_DIR else f"{self.test_name}_polarion_{report_type}.log"

        try:
            requests.packages.urllib3.disable_warnings()
            resp = requests.post(url=job_url, timeout=20, files=files,
                                 verify=False,
                                 auth=HTTPBasicAuth(self.polation_config['user'],
                                                    self.polation_config['pass']))
            write_logs_into_file(resp.text, log_path)
            resp.raise_for_status()
        except requests.HTTPError as ex:
            print("The server responded with error -", ex)

        state = resp.text.replace("\n", "")
        state = json.loads(state)

        job_id = state['files'][Path(report).name]['job-ids'][0]
        if job_id == 0:
            raise ValueError(f"Polarion: Error in the file or data to import to Polarion: {report}")

        return job_id

    def query_report_status(self, report_type, job_id):
        """Query created Polarion report for errors."""
        job_url = f"{self.polation_config['server']}/import/{report_type}-log?jobId={job_id}"
        print(f"Polarion: Checking {report_type} import job status at: {job_url}")

        log_path = f"{LOGS_DIR}/{self.test_name}_polarion_{report_type}.log" \
            if LOGS_DIR else f"{self.test_name}_polarion_{report_type}.log"

        # Generation of the report may take time.
        # Retry a number of times to fetch the report.
        timeout = 0
        max_timeout = 50
        wait_time = 10
        while timeout < max_timeout:
            try:
                requests.packages.urllib3.disable_warnings()
                resp = requests.get(url=job_url, timeout=40, verify=False,
                                    auth=HTTPBasicAuth(self.polation_config['user'],
                                                       self.polation_config['pass']))
                write_logs_into_file(resp.text, log_path)
                resp.raise_for_status()
            except requests.HTTPError as ex:
                print("The server responded with error -", ex)

            # Convert html numeric character references into unicode characters
            raw_state = html.unescape(resp.text).replace("\n", "")
            if "Message sent" in raw_state:
                break

            timeout += 1
            sleep(wait_time)
        else:
            raise ValueError("Polarion: Creation of the report failed")

        err_msg = f"Polarion: Importing {report_type} to Polarion did not complete successfully"
        if "failed" in raw_state:
            raise ValueError(err_msg)

        # Extract dictionary out of the response body
        state = json.loads(re.search('({.+})', raw_state).group(0))
        if "passed" not in state['status']:
            raise ValueError(err_msg)

        if report_type == "xunit":
            print(f"Polarion: The TestRun url - {state['testrun-url']}")

        print("Polarion: The report has been created successfully")


def main():
    args = parse_args()

    report = PolarionProcessReports(args.config, args.path, args.prefix)
    report.process_reports()


if __name__ == '__main__':
    main()

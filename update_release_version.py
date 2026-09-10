#!/usr/bin/env python3
"""
Automated Release Version Update Tool
Automates file updates needed for testing a new ACM/Submariner release version.
"""

import argparse
import os
import sys
import subprocess
import re
from pathlib import Path
import yaml


class ReleaseVersionUpdater:
    def __init__(self, args):
        self.acm_version = args.acm_version
        self.acm_snapshot = args.acm_snapshot
        self.submariner_version = args.submariner_version
        self.ocp_hub = args.ocp_hub
        self.ocp_aws = args.ocp_aws
        self.ocp_gcp = args.ocp_gcp
        self.ocp_azure = args.ocp_azure
        self.mce_snapshot = args.mce_snapshot
        self.template_path = args.template_path if hasattr(args, 'template_path') and args.template_path else None

        # File paths
        self.repo_root = Path(__file__).parent.absolute()
        self.imagedigest_file = self.repo_root / "imagedigest.yaml"
        self.submariner_config_file = self.repo_root / "manifests" / "submariner-config.yaml"
        self.variables_file = self.repo_root / "variables"
        self.jenkinsfile = self.repo_root / "jenkinsfiles" / "aws-gcp-azure.Jenkinsfile"
        self.jenkinsfile2 = self.repo_root / "jenkinsfiles" / "aws-gcp-azure2.Jenkinsfile"
        self.jenkinsfile_osp = self.repo_root / "jenkinsfiles" / "aws-osp-vsphere.Jenkinsfile"
        self.jenkinsfile_aro = self.repo_root / "jenkinsfiles" / "azure-rosa-aro.Jenkinsfile"
        self.konflux_marker_file = self.repo_root / "lib" / "submariner_prepare" / "downstream_prepare.sh"
        self.prerequisites_file = self.repo_root / "lib" / "common" / "prerequisites.sh"
        self.run_sh_file = self.repo_root / "run.sh"
        self.requirements_file = self.repo_root / "requirements.yml"
        self.gitignore_file = self.repo_root / ".gitignore"
        self.dockerfile = self.repo_root / "Dockerfile"
        self.casc_root = Path("/home/pyadav/jenkins/skynet-casc-qe")
        self.config_output_dir = self.casc_root / "secrets"
        self.casc_file = self.casc_root / "casc.yaml"

        # Default template path: use the most recent matching file in the repo itself
        self.default_template_path = None

        # Derived values
        self.submariner_version_dash = self.submariner_version.replace(".", "-")
        self.acm_version_underscore = self.acm_version.replace(".", "_")
        self.branch_name = f"release-{self.acm_version}"

        self.changes_made = []
        self.generated_config_name = None

    def run(self):
        """Main execution flow"""
        print("=" * 70)
        print("ACM/Submariner Release Version Update Tool")
        print("=" * 70)
        print(f"\nACM Version: {self.acm_version}")
        print(f"ACM Snapshot: {self.acm_snapshot}")
        print(f"Submariner Version: {self.submariner_version}")
        print(f"OCP Hub: {self.ocp_hub}")
        print(f"OCP AWS: {self.ocp_aws}")
        print(f"OCP GCP: {self.ocp_gcp}")
        print(f"OCP Azure: {self.ocp_azure}")
        print(f"MCE Snapshot: {self.mce_snapshot}")
        print("=" * 70)

        # Step 1: Check/switch branch
        self.check_and_switch_branch()

        # Step 2: Verify Konflux code is present in the branch
        self.verify_konflux_code()

        # Step 3: Update imagedigest.yaml
        self.update_imagedigest()

        # Step 4: Update submariner-config.yaml
        self.update_submariner_config()

        # Step 5: Update variables file
        self.update_variables()

        # Step 6: Generate config YML file
        self.generate_config_yml()

        # Step 7: Update Jenkinsfiles (SUBMARINER_CONFIG defaultValue + modern params)
        self.update_jenkinsfile()
        self.update_secondary_jenkinsfiles()

        # Step 8: Update prerequisites.sh get_subctl_for_testing
        self.update_prerequisites()

        # Step 9: Update run.sh deploy_submariner
        self.update_run_sh()

        # Step 10: Update requirements.yml, .gitignore, Dockerfile
        self.update_misc_files()

        # Step 11: Register the generated config secret in casc.yaml
        self.update_casc_yaml()

        # Step 12: Display summary
        self.display_summary()

    def check_and_switch_branch(self):
        """Check current branch and switch if necessary"""
        print(f"\n[1/7] Checking git branch...")

        try:
            # Get current branch
            result = subprocess.run(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                cwd=self.repo_root,
                capture_output=True,
                text=True,
                check=True
            )
            current_branch = result.stdout.strip()

            if current_branch == self.branch_name:
                print(f"✓ Already on branch '{self.branch_name}'")
            else:
                print(f"Current branch: {current_branch}")
                print(f"Target branch: {self.branch_name}")

                # Check if target branch exists locally
                result = subprocess.run(
                    ["git", "rev-parse", "--verify", self.branch_name],
                    cwd=self.repo_root,
                    capture_output=True,
                    text=True
                )

                if result.returncode == 0:
                    # Branch exists locally, switch to it
                    subprocess.run(
                        ["git", "checkout", self.branch_name],
                        cwd=self.repo_root,
                        check=True
                    )
                    print(f"✓ Switched to branch '{self.branch_name}'")
                else:
                    # Check if branch exists on remote
                    result = subprocess.run(
                        ["git", "ls-remote", "--heads", "origin", self.branch_name],
                        cwd=self.repo_root,
                        capture_output=True,
                        text=True
                    )

                    if result.stdout.strip():
                        # Branch exists on remote, fetch and checkout
                        print(f"Found '{self.branch_name}' on remote origin")
                        subprocess.run(
                            ["git", "fetch", "origin", self.branch_name],
                            cwd=self.repo_root,
                            check=True
                        )
                        subprocess.run(
                            ["git", "checkout", "-b", self.branch_name, f"origin/{self.branch_name}"],
                            cwd=self.repo_root,
                            check=True
                        )
                        print(f"✓ Checked out '{self.branch_name}' from remote")
                    else:
                        print(f"⚠ WARNING: Branch '{self.branch_name}' does not exist locally or on remote!")
                        response = input(f"Create new branch '{self.branch_name}'? (y/n): ")
                        if response.lower() == 'y':
                            subprocess.run(
                                ["git", "checkout", "-b", self.branch_name],
                                cwd=self.repo_root,
                                check=True
                            )
                            print(f"✓ Created and switched to branch '{self.branch_name}'")
                        else:
                            print("✗ Aborting — edits must run on the target branch.")
                            sys.exit(1)

        except subprocess.CalledProcessError as e:
            print(f"✗ FATAL: Git operation failed: {e}")
            print(f"Cannot switch to branch '{self.branch_name}' — stash or commit your changes first.")
            sys.exit(1)

    # Konflux block injected when missing from older branches.
    # Replaces the old UMB/IIB-based get_latest_iib with the FBC-based version
    # and adds all Konflux constants/functions needed for downstream Submariner testing.
    KONFLUX_BLOCK = r'''# ━━━ KONFLUX CONSTANTS ━━━
readonly KONFLUX_API="${KONFLUX_CLUSTER_API:-https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443}"
readonly KONFLUX_NAMESPACE="submariner-tenant"

# Global flag to track Konflux login status
KONFLUX_LOGGED_IN=false

# ━━━ KONFLUX LOGIN ━━━
# Login to Konflux cluster using token, username/password, or interactive web login
function login_to_konflux() {
    # If already logged in, skip
    if [[ "$KONFLUX_LOGGED_IN" == "true" ]]; then
        return 0
    fi

    INFO "Logging into Konflux cluster at $KONFLUX_API"

    # Check prerequisites
    command -v oc &>/dev/null || ERROR "oc command not found - install OpenShift CLI"

    # Save current KUBECONFIG
    local saved_kubeconfig="${KUBECONFIG:-}"
    unset KUBECONFIG

    # Check if already logged in
    if oc whoami &>/dev/null 2>&1; then
        local server
        server=$(oc whoami --show-server 2>/dev/null || echo "")
        if [[ "$server" =~ "kflux" ]]; then
            INFO "Already logged into Konflux cluster"
            KONFLUX_LOGGED_IN=true
            [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
            return 0
        fi
    fi

    # Try token authentication if token is set
    if [[ -n "${KONFLUX_CLUSTER_TOKEN}" ]]; then
        INFO "Attempting token authentication to Konflux"
        if oc login --token="${KONFLUX_CLUSTER_TOKEN}" --server="${KONFLUX_API}" --insecure-skip-tls-verify=true &>/dev/null; then
            if oc whoami &>/dev/null 2>&1; then
                INFO "Successfully logged into Konflux using token"
                KONFLUX_LOGGED_IN=true
                [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
                return 0
            fi
        fi
        WARNING "Token authentication failed - token may be invalid or expired"
        WARNING "Falling back to interactive web login"
    fi

    # Try username/password authentication if credentials are set
    if [[ -n "${KONFLUX_CLUSTER_USER}" && -n "${KONFLUX_CLUSTER_PASS}" ]]; then
        INFO "Attempting username/password authentication to Konflux"
        if oc login -u "${KONFLUX_CLUSTER_USER}" -p "${KONFLUX_CLUSTER_PASS}" --server="${KONFLUX_API}" --insecure-skip-tls-verify=true &>/dev/null; then
            if oc whoami &>/dev/null 2>&1; then
                INFO "Successfully logged into Konflux using username/password"
                KONFLUX_LOGGED_IN=true
                [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
                return 0
            fi
        fi
        WARNING "Username/password authentication failed"
        WARNING "Falling back to interactive web login"
    fi

    # No credentials or credentials failed - try interactive web login
    INFO "No valid credentials found - initiating interactive web login to Konflux"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Konflux Interactive Login Required"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Opening browser for authentication to Konflux cluster..."
    echo "Server: ${KONFLUX_API}"
    echo ""
    echo "After successful login, the script will continue automatically."
    echo ""

    # Perform web login (interactive)
    if oc login --web --server="${KONFLUX_API}" --insecure-skip-tls-verify=true; then
        if oc whoami &>/dev/null 2>&1; then
            local server
            server=$(oc whoami --show-server 2>/dev/null || echo "")
            if [[ "$server" =~ "kflux" ]]; then
                local user
                user=$(oc whoami 2>/dev/null)
                INFO "Successfully logged into Konflux cluster (user: $user)"
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                KONFLUX_LOGGED_IN=true
                [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
                return 0
            fi
        fi
    fi

    # Login failed
    [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
    ERROR "Failed to login to Konflux cluster. Please check your credentials and try again."
}

# ━━━ VERSION MATCHING ━━━
function release_matches_version() {
    local release="$1"
    local version="$2"
    local sha_title

    sha_title=$(oc get release "$release" -n "$KONFLUX_NAMESPACE" \
        -o jsonpath='{.metadata.annotations.pac\.test\.appstudio\.openshift\.io/sha-title}' 2>/dev/null || echo "")

    echo "$sha_title" | head -1 | grep -q "v${version}"
}

function snapshot_matches_version() {
    local snapshot="$1"
    local version="$2"
    local sha_title

    sha_title=$(oc get snapshot "$snapshot" -n "$KONFLUX_NAMESPACE" \
        -o jsonpath='{.metadata.annotations.pac\.test\.appstudio\.openshift\.io/sha-title}' 2>/dev/null || echo "")

    if echo "$sha_title" | head -1 | grep -q "v${version}"; then
        return 0
    fi

    return 1
}

# ━━━ GET FBC URL ━━━
# Get FBC catalog URL from Jenkins parameter based on OCP version
function get_latest_iib() {
    INFO "Detecting OCP version to select appropriate FBC URL"

    local kube_conf="$KCONF/$cluster-kubeconfig.yaml"
    local ocp_version
    local ocp_minor
    local fbc_var_name
    local fbc_url

    ocp_version=$(KUBECONFIG="$kube_conf" oc version 2>/dev/null | grep "Server Version: " | tr -s ' ' | cut -d ' ' -f3 | cut -d '.' -f1,2)

    if [[ -z "$ocp_version" ]]; then
        ERROR "Failed to get OCP version from cluster $cluster"
    fi

    ocp_minor="${ocp_version#4.}"
    INFO "Detected OCP version: ${ocp_version}"

    fbc_var_name="FBC_URL_4_${ocp_minor}"
    fbc_url="${!fbc_var_name}"

    if [[ -z "$fbc_url" ]]; then
        ERROR "FBC URL not provided for OCP ${ocp_version}. Please set ${fbc_var_name} parameter in Jenkins."
    fi

    LATEST_IIB="$fbc_url"
    INFO "Using FBC URL from Jenkins parameter ${fbc_var_name}: $LATEST_IIB"
    return 0
}

# Fallback: Get FBC from Snapshots if Release CRs don't exist
function get_fbc_from_snapshots() {
    local ocp_minor="$1"
    local version="$2"

    INFO "Fetching FBC from Snapshots for OCP 4.${ocp_minor}"

    local snapshots
    snapshots=$(oc get snapshots -n "$KONFLUX_NAMESPACE" --sort-by=.metadata.creationTimestamp 2>/dev/null \
        | grep "^submariner-fbc-4-${ocp_minor}-" \
        | awk '{print $1}' || echo "")

    if [[ -z "$snapshots" ]]; then
        ERROR "No snapshots found for OCP 4.${ocp_minor}"
    fi

    local latest_snapshot
    latest_snapshot=$(echo "$snapshots" | tail -1)

    if [[ -z "$latest_snapshot" ]]; then
        ERROR "Failed to get latest snapshot for OCP 4.${ocp_minor}"
    fi

    INFO "Using latest FBC snapshot: $latest_snapshot"

    local catalog_image
    catalog_image=$(oc get snapshot "$latest_snapshot" -n "$KONFLUX_NAMESPACE" \
        -o jsonpath='{.spec.components[0].containerImage}' 2>/dev/null || echo "")

    if [[ -z "$catalog_image" ]]; then
        ERROR "Failed to extract catalog image from snapshot $latest_snapshot"
    fi

    LATEST_IIB="$catalog_image"
    INFO "Detected FBC from Konflux Snapshot: $LATEST_IIB (contains multiple Submariner versions)"
}

# ━━━ GET SUBCTL FROM KONFLUX ━━━
# Sets global variable: KONFLUX_SUBCTL_IMAGE
function get_konflux_subctl_image() {
    INFO "Fetch subctl container image from Konflux snapshots"

    local submariner_version="$SUBMARINER_VERSION_INSTALL"
    local version_short
    local application_name
    local component_name
    local subctl_image

    if [[ "$submariner_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        version_short="${submariner_version%.*}"
    else
        version_short="$submariner_version"
    fi
    version_short="${version_short//./-}"

    application_name="submariner-${version_short}"
    component_name="subctl-${version_short}"

    INFO "Looking for subctl in application: ${application_name}, component: ${component_name}"

    local saved_kubeconfig="${KUBECONFIG:-}"
    unset KUBECONFIG

    login_to_konflux

    local snapshots
    snapshots=$(oc get snapshots -n "$KONFLUX_NAMESPACE" --sort-by=.metadata.creationTimestamp 2>/dev/null \
        | grep "^${application_name}-" \
        | awk '{print $1}' || echo "")

    if [[ -z "$snapshots" ]]; then
        [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
        WARNING "No snapshots found for application ${application_name}"
        return 1
    fi

    local latest_snapshot
    latest_snapshot=$(echo "$snapshots" | tail -1)
    INFO "Using latest snapshot: $latest_snapshot"

    subctl_image=$(oc get snapshot "$latest_snapshot" -n "$KONFLUX_NAMESPACE" \
        -o json 2>/dev/null | jq -r ".spec.components[] | select(.name==\"${component_name}\") | .containerImage" || echo "")

    if [[ -z "$subctl_image" || "$subctl_image" == "null" ]]; then
        [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
        WARNING "Failed to extract subctl image from snapshot $latest_snapshot"
        return 1
    fi

    [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"

    KONFLUX_SUBCTL_IMAGE="$subctl_image"
    INFO "Detected subctl from Konflux Snapshot: $KONFLUX_SUBCTL_IMAGE"
    return 0
}
'''

    def verify_konflux_code(self):
        """Ensure Konflux integration code is present; inject it if missing."""
        print(f"\n[2/7] Verifying Konflux code is present...")

        if not self.konflux_marker_file.exists():
            print(f"✗ FATAL: {self.konflux_marker_file} not found")
            print("Konflux code verification failed — aborting.")
            sys.exit(1)

        with open(self.konflux_marker_file, 'r') as f:
            content = f.read()

        required_markers = [
            "KONFLUX_API",
            "login_to_konflux",
            "get_konflux_subctl_image",
        ]
        missing = [m for m in required_markers if m not in content]

        if not missing:
            print(f"✓ Konflux code verified in {self.konflux_marker_file.relative_to(self.repo_root)}")
            return

        print(f"  Konflux code missing ({', '.join(missing)}) — injecting into {self.konflux_marker_file.name}...")

        # Replace the old get_latest_iib function (and any leading comment lines) with the
        # full Konflux block, which includes the new FBC-based get_latest_iib.
        old_iib_pattern = re.compile(
            r'(?:#[^\n]*\n)*function get_latest_iib\(\) \{.*?\n\}',
            re.DOTALL
        )
        match = old_iib_pattern.search(content)
        if match:
            updated_content = content[:match.start()] + self.KONFLUX_BLOCK + content[match.end():]
        else:
            # No get_latest_iib — insert before create_catalog_source or append at end
            anchor = re.search(r'\nfunction create_catalog_source', content)
            if anchor:
                updated_content = content[:anchor.start()] + '\n' + self.KONFLUX_BLOCK.rstrip('\n') + content[anchor.start():]
            else:
                updated_content = content.rstrip('\n') + '\n\n' + self.KONFLUX_BLOCK

        with open(self.konflux_marker_file, 'w') as f:
            f.write(updated_content)

        rel = self.konflux_marker_file.relative_to(self.repo_root)
        self.changes_made.append(f"{rel}: injected Konflux constants and functions")
        print(f"✓ Konflux code injected into {rel}")

    # Template for imagedigest.yaml — used when the file doesn't exist on the branch.
    # Mirrors pattern matches what release-2.15+ branches use.
    IMAGEDIGEST_TEMPLATE = """\
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: subm-bundle
spec:
  imageDigestMirrors:
  - source: registry.redhat.io/rhacm2/submariner-operator-bundle
    mirrors:
    - quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-{ver}
  - source: registry.redhat.io/rhacm2/submariner-gateway-rhel9
    mirrors:
    - quay.io/redhat-user-workloads/submariner-tenant/submariner-gateway-{ver}
  - source: registry.redhat.io/rhacm2/submariner-rhel9-operator
    mirrors:
    - quay.io/redhat-user-workloads/submariner-tenant/submariner-operator-{ver}
  - source: registry.redhat.io/rhacm2/submariner-route-agent-rhel9
    mirrors:
    - quay.io/redhat-user-workloads/submariner-tenant/submariner-route-agent-{ver}
  - source: registry.redhat.io/rhacm2/submariner-globalnet-rhel9
    mirrors:
    - quay.io/redhat-user-workloads/submariner-tenant/submariner-globalnet-{ver}
  - source: registry.redhat.io/rhacm2/lighthouse-agent-rhel9
    mirrors:
    - quay.io/redhat-user-workloads/submariner-tenant/lighthouse-agent-{ver}
  - source: registry.redhat.io/rhacm2/lighthouse-coredns-rhel9
    mirrors:
    - quay.io/redhat-user-workloads/submariner-tenant/lighthouse-coredns-{ver}
  - source: registry.redhat.io/rhacm2/nettest-rhel9
    mirrors:
    - quay.io/redhat-user-workloads/submariner-tenant/nettest-{ver}
"""

    def update_imagedigest(self):
        """Update imagedigest.yaml with new Submariner version; create it if missing."""
        print(f"\n[3/7] Updating {self.imagedigest_file}...")

        new_version = self.submariner_version_dash

        if not self.imagedigest_file.exists():
            print(f"  File not found — creating {self.imagedigest_file.name} from template...")
            content = self.IMAGEDIGEST_TEMPLATE.format(ver=new_version)
            with open(self.imagedigest_file, 'w') as f:
                f.write(content)
            print(f"✓ Created imagedigest.yaml with version {new_version}")
            self.changes_made.append(f"imagedigest.yaml: created with version {new_version}")
            return

        with open(self.imagedigest_file, 'r') as f:
            content = f.read()

        old_version_pattern = r'submariner-\w+-0-\d+'
        matches = re.findall(old_version_pattern, content)

        if matches:
            old_version_match = re.search(r'0-(\d+)', matches[0])
            if old_version_match:
                old_version = f"0-{old_version_match.group(1)}"
                updated_content = content.replace(old_version, new_version)
                with open(self.imagedigest_file, 'w') as f:
                    f.write(updated_content)
                count = content.count(old_version)
                print(f"✓ Updated {count} occurrences: {old_version} → {new_version}")
                self.changes_made.append(f"imagedigest.yaml: {old_version} → {new_version} ({count} occurrences)")
            else:
                print("⚠ Could not extract old version")
        else:
            print("⚠ No submariner version pattern found")

    def update_submariner_config(self):
        """Update manifests/submariner-config.yaml channel; append it if missing."""
        print(f"\n[4/7] Updating {self.submariner_config_file}...")

        if not self.submariner_config_file.exists():
            print(f"⚠ File not found: {self.submariner_config_file}")
            return

        with open(self.submariner_config_file, 'r') as f:
            content = f.read()

        old_channel_pattern = r'channel: stable-0\.\d+'
        new_channel = f"channel: stable-{self.submariner_version}"

        old_channel_match = re.search(old_channel_pattern, content)
        if old_channel_match:
            old_channel = old_channel_match.group(0)
            updated_content = re.sub(old_channel_pattern, new_channel, content)
            with open(self.submariner_config_file, 'w') as f:
                f.write(updated_content)
            print(f"✓ Updated: {old_channel} → {new_channel}")
            self.changes_made.append(f"submariner-config.yaml: {old_channel} → {new_channel}")
        else:
            # Channel line absent (older branch) — append it under subscriptionConfig
            source_ns_pattern = r'(sourceNamespace: openshift-marketplace)'
            if re.search(source_ns_pattern, content):
                updated_content = re.sub(
                    source_ns_pattern,
                    rf'\1\n    {new_channel}',
                    content
                )
                with open(self.submariner_config_file, 'w') as f:
                    f.write(updated_content)
                print(f"✓ Appended missing channel line: {new_channel}")
                self.changes_made.append(f"submariner-config.yaml: added {new_channel}")
            else:
                print("⚠ Could not find insertion point for channel line")

    def update_variables(self):
        """Update variables file with new ACM version array"""
        print(f"\n[5/7] Updating {self.variables_file}...")

        if not self.variables_file.exists():
            print(f"⚠ File not found: {self.variables_file}")
            return

        with open(self.variables_file, 'r') as f:
            content = f.read()

        # Create new ACM version block
        acm_var_name = f"ACM_{self.acm_version_underscore}"
        new_block = f'''declare -A {acm_var_name}=(
    [acm_version]='{self.acm_version}'
    [submariner_version]='{self.submariner_version}'
    [channel]='stable'
)
export {acm_var_name}'''

        # Find ANY existing ACM block and replace it with the new one
        # Pattern matches: declare -A ACM_X_XX=( ... ) \n export ACM_X_XX
        any_acm_pattern = r'declare -A ACM_\d+_\d+=[^)]*\)\s*export ACM_\d+_\d+'

        match = re.search(any_acm_pattern, content, re.DOTALL)

        if match:
            old_block = match.group(0)
            # Extract old version name for logging
            old_var_match = re.search(r'ACM_\d+_\d+', old_block)
            old_var_name = old_var_match.group(0) if old_var_match else "unknown"

            # Replace the first (and should be only) ACM block with the new one
            updated_content = re.sub(any_acm_pattern, new_block, content, count=1, flags=re.DOTALL)

            print(f"✓ Replaced {old_var_name} with {acm_var_name}")
            self.changes_made.append(f"variables: Replaced {old_var_name} with {acm_var_name}")
        else:
            # No existing ACM block found, create one after the comment line
            comment_pattern = r'# Declare associative arrays for acm/submariner versions'
            comment_match = re.search(comment_pattern, content)

            if comment_match:
                insert_pos = comment_match.end()
                # Find the end of the line
                newline_pos = content.find('\n', insert_pos)
                if newline_pos != -1:
                    insert_pos = newline_pos + 1
                updated_content = content[:insert_pos] + new_block + "\n\n" + content[insert_pos:]
                print(f"✓ Created new {acm_var_name} block")
                self.changes_made.append(f"variables: Created {acm_var_name}")
            else:
                print(f"⚠ Could not find insertion point for {acm_var_name}")
                return

        with open(self.variables_file, 'w') as f:
            f.write(updated_content)

    def generate_config_yml(self):
        """Generate new config YML file at target directory"""
        print(f"\n[6/7] Generating config YML file...")

        # Determine which template to use
        template_file = None

        if self.template_path:
            # Use user-specified template
            template_file = Path(self.template_path)
            if not template_file.exists():
                print(f"⚠ Specified template not found: {template_file}")
                return
            print(f"Using specified template: {template_file}")
        else:
            # Try to find template in repo
            template_files = list(self.repo_root.glob("acm-*-subm-*-aws-gcp-azure.yml"))

            if template_files:
                # Use the most recent template from repo
                template_file = sorted(template_files, key=lambda x: x.stat().st_mtime, reverse=True)[0]
                print(f"Using template from repo: {template_file.name}")
            else:
                print("⚠ No template config files found")
                print(f"⚠ Searched: {self.repo_root}/acm-*-subm-*-aws-gcp-azure.yml")
                print("⚠ Provide a template via --template-path or place one in the repo root")
                return

        with open(template_file, 'r') as f:
            config_content = f.read()

        # Update version fields
        config_content = re.sub(r'openshift_version: "[\d.]+"', f'openshift_version: "{self.ocp_hub}"', config_content, count=1)
        config_content = re.sub(r'acm_version: "[\d.]+"', f'acm_version: "{self.acm_version}"', config_content)
        config_content = re.sub(r'snapshot: ".*?"', f'snapshot: "{self.acm_snapshot}"', config_content)
        config_content = re.sub(r'mce_snapshot: ".*?"', f'mce_snapshot: "{self.mce_snapshot}"', config_content)
        config_content = re.sub(r'acm_catalog_tag: ".*?"', f'acm_catalog_tag: "{self.acm_snapshot}"', config_content)
        config_content = re.sub(r'mce_catalog_tag: ".*?"', f'mce_catalog_tag: "{self.mce_snapshot}"', config_content)

        # Update hive_cluster_version for each platform
        # AWS
        config_content = re.sub(
            r'(- name: submqe-aws.*?hive_cluster_version: )"[\d.]+"',
            rf'\1"{self.ocp_aws}"',
            config_content,
            flags=re.DOTALL
        )

        # GCP
        config_content = re.sub(
            r'(- name: submqe-gcp.*?hive_cluster_version: )"[\d.]+"',
            rf'\1"{self.ocp_gcp}"',
            config_content,
            flags=re.DOTALL
        )

        # Azure
        config_content = re.sub(
            r'(- name: submqe-azure.*?hive_cluster_version: )"[\d.]+"',
            rf'\1"{self.ocp_azure}"',
            config_content,
            flags=re.DOTALL
        )

        # Create output directory if it doesn't exist
        self.config_output_dir.mkdir(parents=True, exist_ok=True)

        # Generate output filename
        output_filename = f"acm-{self.acm_version}-subm-{self.submariner_version}-aws-gcp-azure.yml"
        output_path = self.config_output_dir / output_filename

        with open(output_path, 'w') as f:
            f.write(config_content)

        # Store stem for Jenkinsfile update (credential ID = filename without extension)
        self.generated_config_name = output_path.stem

        print(f"✓ Created: {output_path}")
        self.changes_made.append(f"Created config file: {output_path}")

    # Modern Jenkinsfile parameters block — replaces the old extendedChoice format
    # and adds FBC URL / SUBCTL params used by Konflux-based downstream testing.
    JENKINSFILE_MODERN_PARAMS = """\
                booleanParam(name: 'GLOBALNET', defaultValue: false, description: 'Deploy Globalnet on Submariner'),
                booleanParam(name: 'DOWNSTREAM', defaultValue: true, description: 'Deploy downstream version of Submariner'),
                [$class: 'ChoiceParameter',
                    choiceType: 'PT_CHECKBOX',
                    name: 'JOB_STAGES',
                    description: 'Select the stages of the job to be executed',
                    filterable: false,
                    filterLength: 1,
                    script: [
                        $class: 'GroovyScript',
                        fallbackScript: [
                            classpath: [],
                            sandbox: true,
                            script: 'return ["ERROR"]'
                        ],
                        script: [
                            classpath: [],
                            sandbox: true,
                            script: \'\'\'
                                return [
                                    'Deploy OCP cluster:selected',
                                    'Deploy Managed OCP',
                                    'Deploy ACM Hub:selected',
                                    'Deploy Clusters by ACM:selected',
                                    'Import OCP into ACM Hub',
                                    'Submariner Validate prerequisites:selected',
                                    'Submariner Deploy:selected',
                                    'Submariner Test - E2E:selected',
                                    'Submariner Test - Cypress UI:selected',
                                    'Report to Polarion:selected'
                                ]
                            \'\'\'
                        ]
                    ]
                ],
                [$class: 'ChoiceParameter',
                    choiceType: 'PT_CHECKBOX',
                    name: 'PLATFORM',
                    description: 'The managed clusters platform that should be tested',
                    filterable: false,
                    filterLength: 1,
                    script: [
                        $class: 'GroovyScript',
                        fallbackScript: [
                            classpath: [],
                            sandbox: true,
                            script: 'return ["ERROR"]'
                        ],
                        script: [
                            classpath: [],
                            sandbox: true,
                            script: \'\'\'
                                return [
                                    'aws:selected',
                                    'gcp:selected',
                                    'azure:selected',
                                    'vsphere',
                                    'osp',
                                    'aro',
                                    'rosa'
                                ]
                            \'\'\'
                        ]
                    ]
                ],
                booleanParam(name: 'SUBMARINER_GATEWAY_RANDOM', defaultValue: true, description: 'Deploy two submariner gateways on one of the clusters'),
                string(name: 'NODE_TO_LABEL_AS_GW', defaultValue: '', description: 'Specify cluster node to be manually labeled as Submariner Gateway'),
                string(name: 'FBC_URL_4_19', defaultValue: '', description: 'FBC (File-Based Catalog) image URL for OCP 4.19'),
                string(name: 'FBC_URL_4_20', defaultValue: '', description: 'FBC (File-Based Catalog) image URL for OCP 4.20'),
                string(name: 'FBC_URL_4_21', defaultValue: '', description: 'FBC (File-Based Catalog) image URL for OCP 4.21'),
                string(name: 'FBC_URL_4_22', defaultValue: '', description: 'FBC (File-Based Catalog) image URL for OCP 4.22'),
                string(name: 'SUBCTL_DOWNLOAD_URL', defaultValue: '', description: 'Subctl container image URL (required)'),
                credentials(name: 'SUBMARINER_CONFIG', defaultValue: '{config_name}', description: 'Submariner config for environment deploy',
                    required: true, credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl')"""

    def update_jenkinsfile(self):
        """Update aws-gcp-azure.Jenkinsfile: modernise structure if needed and set SUBMARINER_CONFIG defaultValue."""
        print(f"\n[7/7] Updating {self.jenkinsfile}...")

        if not self.jenkinsfile.exists():
            print(f"⚠ File not found: {self.jenkinsfile}")
            return

        if not hasattr(self, 'generated_config_name') or not self.generated_config_name:
            print("⚠ No generated config name available — skipping Jenkinsfile update")
            return

        with open(self.jenkinsfile, 'r') as f:
            content = f.read()

        # If the old extendedChoice format is still present, replace the entire params block
        if "extendedChoice(name: 'JOB_STAGES'" in content:
            modern_params = self.JENKINSFILE_MODERN_PARAMS.format(
                config_name=self.generated_config_name
            )
            # Replace everything between the opening `parameters([` and its closing `])`
            old_params_pattern = re.compile(
                r"(parameters\(\[)(.*?)(\]\))",
                re.DOTALL
            )
            updated_content = old_params_pattern.sub(
                lambda m: m.group(1) + '\n' + modern_params + '\n            ' + m.group(3),
                content
            )
            with open(self.jenkinsfile, 'w') as f:
                f.write(updated_content)
            print("✓ Modernised Jenkinsfile: replaced extendedChoice params with ChoiceParameter format")
            print(f"✓ Added FBC URL and SUBCTL_DOWNLOAD_URL parameters")
            print(f"✓ Set SUBMARINER_CONFIG defaultValue: '{self.generated_config_name}'")
            self.changes_made.append(
                f"aws-gcp-azure.Jenkinsfile: modernised params + SUBMARINER_CONFIG → '{self.generated_config_name}'"
            )
            return

        # Already modern — just update the SUBMARINER_CONFIG defaultValue
        pattern = r"(credentials\(name: 'SUBMARINER_CONFIG', defaultValue: ')[^']*(')"
        match = re.search(pattern, content)
        if match:
            old_value = match.group(0).split("'")[3]
            updated_content = re.sub(pattern, rf"\g<1>{self.generated_config_name}\g<2>", content)
            with open(self.jenkinsfile, 'w') as f:
                f.write(updated_content)
            print(f"✓ Updated SUBMARINER_CONFIG defaultValue: '{old_value}' → '{self.generated_config_name}'")
            self.changes_made.append(
                f"aws-gcp-azure.Jenkinsfile: SUBMARINER_CONFIG defaultValue → '{self.generated_config_name}'"
            )
        else:
            print("⚠ SUBMARINER_CONFIG credentials parameter not found in Jenkinsfile")

    # FBC params block inserted before the credentials line in secondary Jenkinsfiles
    FBC_PARAMS_BLOCK = """\
                string(name: 'FBC_URL_4_19', defaultValue: '', description: 'FBC (File-Based Catalog) image URL for OCP 4.19'),
                string(name: 'FBC_URL_4_20', defaultValue: '', description: 'FBC (File-Based Catalog) image URL for OCP 4.20'),
                string(name: 'FBC_URL_4_21', defaultValue: '', description: 'FBC (File-Based Catalog) image URL for OCP 4.21'),
                string(name: 'FBC_URL_4_22', defaultValue: '', description: 'FBC (File-Based Catalog) image URL for OCP 4.22'),
                string(name: 'SUBCTL_DOWNLOAD_URL', defaultValue: '', description: 'Subctl container image URL (required)'),
"""

    def _update_secondary_jenkinsfile(self, jf_path, config_suffix):
        """Add FBC params and update SUBMARINER_CONFIG in a secondary Jenkinsfile."""
        if not jf_path.exists():
            print(f"  ⚠ File not found: {jf_path}")
            return

        with open(jf_path, 'r') as f:
            content = f.read()

        changed = False
        new_config = f"acm-{self.acm_version}-subm-{self.submariner_version}-{config_suffix}"

        # Insert FBC params before credentials line if not already present
        if 'FBC_URL_4_19' not in content:
            cred_pattern = r"(                credentials\(name: 'SUBMARINER_CONFIG')"
            content = re.sub(cred_pattern, self.FBC_PARAMS_BLOCK + r'\1', content)
            changed = True

        # Update SUBMARINER_CONFIG defaultValue
        cred_value_pattern = r"(credentials\(name: 'SUBMARINER_CONFIG', defaultValue: ')[^']*(')"
        match = re.search(cred_value_pattern, content)
        if match:
            old_val = match.group(0).split("'")[3]
            content = re.sub(cred_value_pattern, rf"\g<1>{new_config}\g<2>", content)
            changed = True
            print(f"  ✓ {jf_path.name}: SUBMARINER_CONFIG '{old_val}' → '{new_config}'")
        else:
            print(f"  ⚠ {jf_path.name}: SUBMARINER_CONFIG not found")

        if 'FBC_URL_4_19' in content and changed:
            print(f"  ✓ {jf_path.name}: FBC URL + SUBCTL_DOWNLOAD_URL params added")

        if changed:
            with open(jf_path, 'w') as f:
                f.write(content)
            self.changes_made.append(f"{jf_path.name}: FBC params + SUBMARINER_CONFIG → '{new_config}'")

    def update_secondary_jenkinsfiles(self):
        """Update aws-gcp-azure2, aws-osp-vsphere, and azure-rosa-aro Jenkinsfiles."""
        print(f"\n[7b] Updating secondary Jenkinsfiles...")
        self._update_secondary_jenkinsfile(self.jenkinsfile2, "aws-gcp-azure2")
        self._update_secondary_jenkinsfile(self.jenkinsfile_osp, "aws-osp-vsphere")
        self._update_secondary_jenkinsfile(self.jenkinsfile_aro, "azure-rosa-aro")

    # Modern get_subctl_for_testing function using SUBCTL_DOWNLOAD_URL env var
    SUBCTL_FUNCTION = r'''function get_subctl_for_testing() {
    INFO "Installing subctl client"

    local subctl_version
    local subctl_download_url
    subctl_version=$(fetch_installed_submariner_version)

    # Check if SUBCTL_DOWNLOAD_URL is provided as environment variable
    if [[ -z "${SUBCTL_DOWNLOAD_URL}" ]]; then
        ERROR "SUBCTL_DOWNLOAD_URL environment variable is not set. Please provide subctl download URL through Jenkins parameter."
    fi

    subctl_download_url="$SUBCTL_DOWNLOAD_URL"
    INFO "Using subctl download URL from Jenkins parameter: $subctl_download_url"

    INFO "Extracting subctl from container image: $subctl_download_url"

    # Try multiple paths for different image structures
    # Standard images use /dist/, Konflux images use /usr/local/bin/
    local extracted=false

    # Try path 1: /dist/subctl-*-linux-amd64.tar.xz (standard downstream path)
    if oc image extract --insecure=true "$subctl_download_url" --path=/dist/subctl-*-linux-amd64.tar.xz:./ --confirm 2>/dev/null; then
        if ls subctl-*-linux-amd64.tar.xz 1>/dev/null 2>&1; then
            extracted=true
            INFO "Extracted subctl from /dist/ path"
        fi
    fi

    # Try path 2: /usr/local/bin/subctl (Konflux images)
    if [[ "$extracted" == "false" ]]; then
        INFO "Trying alternative extraction path for Konflux image..."
        if oc image extract --insecure=true "$subctl_download_url" --path=/usr/local/bin/subctl:./ --confirm 2>/dev/null; then
            if [[ -f subctl ]]; then
                mkdir -p subctl-temp
                mv subctl "subctl-temp/subctl-v${subctl_version}-linux-amd64"
                tar -cJf subctl.tar.xz -C subctl-temp "subctl-v${subctl_version}-linux-amd64"
                rm -rf subctl-temp
                extracted=true
                INFO "Extracted subctl from /usr/local/bin/ path (Konflux)"
            fi
        fi
    fi

    # Try path 3: /usr/bin/subctl (fallback)
    if [[ "$extracted" == "false" ]]; then
        if oc image extract --insecure=true "$subctl_download_url" --path=/usr/bin/subctl:./ --confirm 2>/dev/null; then
            if [[ -f subctl ]]; then
                mkdir -p subctl-temp
                mv subctl "subctl-temp/subctl-v${subctl_version}-linux-amd64"
                tar -cJf subctl.tar.xz -C subctl-temp "subctl-v${subctl_version}-linux-amd64"
                rm -rf subctl-temp
                extracted=true
                INFO "Extracted subctl from /usr/bin/ path"
            fi
        fi
    fi

    if [[ "$extracted" == "false" ]]; then
        ERROR "Failed to extract subctl binary from $subctl_download_url. Tried paths: /dist/, /usr/local/bin/, and /usr/bin/"
    fi

    # If we extracted a tar.xz directly, rename it
    if ls subctl-*-linux-amd64.tar.xz 1>/dev/null 2>&1; then
        mv subctl-*-linux-amd64.tar.xz subctl.tar.xz
    fi

    INFO "Submariner addon version - $subctl_version"
    INFO "Downloaded subctl from - $subctl_download_url"

    tar xfJ subctl.tar.xz

    mkdir -p "$HOME"/.local/bin
    install subctl*linux-amd64 "$HOME"/.local/bin/subctl
    rm -f subctl.tar.xz subctl*linux-amd64

    # Add local BIN dir to PATH
    [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
    INFO "Subctl has been downloaded and placed under $HOME/.local/bin/"
    subctl version
}'''

    def update_prerequisites(self):
        """Replace old get_subctl_for_testing with the Konflux-aware version."""
        print(f"\n[8] Updating {self.prerequisites_file.relative_to(self.repo_root)}...")

        if not self.prerequisites_file.exists():
            print(f"  ⚠ File not found: {self.prerequisites_file}")
            return

        with open(self.prerequisites_file, 'r') as f:
            content = f.read()

        if 'SUBCTL_DOWNLOAD_URL' in content:
            print(f"  ✓ Already up to date")
            return

        old_fn_pattern = re.compile(
            r'function get_subctl_for_testing\(\) \{.*?\n\}',
            re.DOTALL
        )
        match = old_fn_pattern.search(content)
        if match:
            updated_content = content[:match.start()] + self.SUBCTL_FUNCTION + content[match.end():]
            with open(self.prerequisites_file, 'w') as f:
                f.write(updated_content)
            print(f"  ✓ Replaced get_subctl_for_testing with Konflux-aware version")
            self.changes_made.append("lib/common/prerequisites.sh: updated get_subctl_for_testing")
        else:
            print(f"  ⚠ get_subctl_for_testing function not found")

    def update_run_sh(self):
        """Add create_idms_and_icsp_combined() call in deploy_submariner if missing."""
        print(f"\n[9] Updating {self.run_sh_file.relative_to(self.repo_root)}...")

        if not self.run_sh_file.exists():
            print(f"  ⚠ File not found: {self.run_sh_file}")
            return

        with open(self.run_sh_file, 'r') as f:
            content = f.read()

        if 'create_idms_and_icsp_combined' in content:
            print(f"  ✓ Already up to date")
            return

        # Insert after create_icsp call inside the DOWNSTREAM block
        old = '        create_icsp\n\n        if [[ "$PLATFORM" =~ "roks" ]]'
        new = ('        create_icsp\n\n'
               '        # Create IDMS (imagedigest.yaml) and submariner bundle ICSP before CatalogSource\n'
               '        # This ensures image mirrors are configured before FBC is applied\n'
               '        create_idms_and_icsp_combined\n\n'
               '        if [[ "$PLATFORM" =~ "roks" ]]')

        if old in content:
            updated_content = content.replace(old, new, 1)
            with open(self.run_sh_file, 'w') as f:
                f.write(updated_content)
            print(f"  ✓ Added create_idms_and_icsp_combined() call")
            self.changes_made.append("run.sh: added create_idms_and_icsp_combined() in deploy_submariner")
        else:
            print(f"  ⚠ Could not find insertion point in run.sh")

    def _get_file_from_main(self, rel_path):
        """Return the content of a file from the main branch, or None on failure."""
        try:
            result = subprocess.run(
                ["git", "show", f"main:{rel_path}"],
                cwd=self.repo_root,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout
        except subprocess.CalledProcessError:
            return None

    def _sync_file_from_main(self, rel_path, description=None):
        """Overwrite a local file with its content from main if they differ."""
        local_file = self.repo_root / rel_path
        main_content = self._get_file_from_main(rel_path)

        if main_content is None:
            print(f"  ⚠ {rel_path}: not found on main branch — skipping")
            return

        if local_file.exists():
            with open(local_file, 'r') as f:
                local_content = f.read()
            if local_content == main_content:
                print(f"  ✓ {rel_path}: already up to date")
                return

        with open(local_file, 'w') as f:
            f.write(main_content)
        label = description or rel_path
        print(f"  ✓ {rel_path}: synced from main")
        self.changes_made.append(f"{label}: synced from main")

    def update_misc_files(self):
        """Sync miscellaneous files from main: SubmarinerAgentPod.yaml, requirements.yml, .gitignore, Dockerfile."""
        print(f"\n[10] Updating miscellaneous files (syncing from main)...")

        self._sync_file_from_main("jenkinsfiles/SubmarinerAgentPod.yaml")
        self._sync_file_from_main("requirements.yml")
        self._sync_file_from_main(".gitignore")
        self._sync_file_from_main("Dockerfile")

    def update_casc_yaml(self):
        """Register the generated config file as a GLOBAL file credential in casc.yaml.

        Appends a `- file:` block (grouped under an `# acm_X.Y_subm_Z.W` comment) to the
        credentials list, mirroring the existing entries e.g.:

          # acm_2.13_subm_0.20
          - file:
              scope: GLOBAL
              id: "acm-2.13-subm-0.20-aws-gcp-azure"
              fileName: "acm-2.13-subm-0.20-aws-gcp-azure.yml"
              secretBytes: "${readFileBase64:/var/run/secrets/casc-secret/acm-2.13-subm-0.20-aws-gcp-azure.yml}"
              description: "acm-2.13-subm-0.20-aws-gcp-azure"
        """
        print(f"\n[11] Registering config secret in {self.casc_file}...")

        if not self.casc_file.exists():
            print(f"  ⚠ File not found: {self.casc_file}")
            return

        if not self.generated_config_name:
            print("  ⚠ No generated config name available — skipping casc.yaml update")
            return

        with open(self.casc_file, 'r') as f:
            content = f.read()

        cred_id = self.generated_config_name  # e.g. acm-2.17-subm-0.24-aws-gcp-azure
        file_name = f"{cred_id}.yml"
        comment = f"# acm_{self.acm_version}_subm_{self.submariner_version}"

        # Skip if this credential id is already registered
        if f'id: "{cred_id}"' in content:
            print(f"  ✓ Already registered: {cred_id}")
            return

        # Indentation of list items ("          - file:") is 10 spaces; keys are 14 spaces.
        indent_item = " " * 10
        indent_key = " " * 14
        entry = (
            f"{indent_item}{comment}\n"
            f"{indent_item}- file:\n"
            f"{indent_key}scope: GLOBAL\n"
            f'{indent_key}id: "{cred_id}"\n'
            f'{indent_key}fileName: "{file_name}"\n'
            f'{indent_key}secretBytes: "${{readFileBase64:/var/run/secrets/casc-secret/{file_name}}}"\n'
            f'{indent_key}description: "{cred_id}"\n'
        )

        # Insert before the top-level `jobs:` section (end of the credentials list).
        jobs_match = re.search(r'\n\njobs:', content)
        if jobs_match:
            insert_pos = jobs_match.start()
            updated_content = content[:insert_pos] + "\n" + entry + content[insert_pos:]
        else:
            # No jobs section — append at end of file
            updated_content = content.rstrip('\n') + "\n" + entry

        with open(self.casc_file, 'w') as f:
            f.write(updated_content)

        print(f"  ✓ Added file credential '{cred_id}' to casc.yaml")
        self.changes_made.append(f"casc.yaml: registered file credential '{cred_id}'")

    def display_summary(self):
        """Display summary of all changes"""
        print("\n" + "=" * 70)
        print("SUMMARY OF CHANGES")
        print("=" * 70)

        if self.changes_made:
            for i, change in enumerate(self.changes_made, 1):
                print(f"{i}. {change}")
        else:
            print("No changes were made.")

        print("\n" + "=" * 70)
        print("✓ Update completed successfully!")
        print("Files have been modified. Please review and commit manually.")
        print("=" * 70)


def main():
    parser = argparse.ArgumentParser(
        description="Automated Release Version Update Tool for ACM/Submariner testing",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example usage:
  python update_release_version.py \\
    --acm-version 2.17 \\
    --acm-snapshot latest-2.17 \\
    --submariner-version 0.24 \\
    --ocp-hub 4.22 \\
    --ocp-aws 4.22 \\
    --ocp-gcp 4.21 \\
    --ocp-azure 4.22 \\
    --mce-snapshot latest-2.17
        """
    )

    parser.add_argument("--acm-version", required=True, help="ACM version (e.g., 2.16, 2.17, 5.0)")
    parser.add_argument("--acm-snapshot", required=True, help="ACM snapshot (e.g., latest-2.16)")
    parser.add_argument("--submariner-version", required=True, help="Submariner version (e.g., 0.23, 0.24)")
    parser.add_argument("--ocp-hub", required=True, help="OpenShift version for hub cluster (e.g., 4.21)")
    parser.add_argument("--ocp-aws", required=True, help="OpenShift version for AWS cluster (e.g., 4.22)")
    parser.add_argument("--ocp-gcp", required=True, help="OpenShift version for GCP cluster (e.g., 4.21)")
    parser.add_argument("--ocp-azure", required=True, help="OpenShift version for Azure cluster (e.g., 4.22)")
    parser.add_argument("--mce-snapshot", required=True, help="MCE snapshot version (e.g., latest-2.11)")
    parser.add_argument("--template-path", required=False, help="Path to custom template YML file (optional)")

    args = parser.parse_args()

    updater = ReleaseVersionUpdater(args)
    updater.run()


if __name__ == "__main__":
    main()

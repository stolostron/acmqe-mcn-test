#!/bin/bash

# Generate Polarion repors and upload to Polarion
# Polarion testcases and testruns will be generated

function report_polarion() {
    INFO "Polarion: Report Polarion test state (internal only)"
    local venv="/tmp/subm"

    python3 -m venv "$venv"
    # shellcheck source=/dev/null
    source "$venv/bin/activate"
    pip install -r requirements.txt

    INFO "PolarionL Process reports"
    python3 lib/reporting/polarion_report.py \
        --config "$POLARION_VARS_FILE" --path "$TESTS_LOGS"
}

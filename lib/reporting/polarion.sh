#!/bin/bash

# Generate Polarion repors and upload to Polarion
# Polarion testcases and testruns will be generated

function report_polarion() {
    INFO "Polarion: Report Polarion test state (internal only)"
    INFO "Polarion: Process reports"
    python3 lib/reporting/polarion_report.py \
        --config "$POLARION_VARS_FILE" --path "$TESTS_LOGS"
}

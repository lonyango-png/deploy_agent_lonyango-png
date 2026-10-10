#!/bin/bash
# deploy_agent.sh: deploys, runs and archives the attendance tracker
# Run it from the repo root so that ./templates is found

TEMPLATES_DIR="./templates"

# ---------- Feature 1, step 1: pre-flight checks ----------
preflight_checks() {
    echo "[1/4] Running pre-flight checks..."
    local missing=0
    for tool in python3 zip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "  ERROR: '$tool' is not installed." >&2
            missing=1
        fi
    done
    [ "$missing" -eq 1 ] && { echo "Install the missing tool(s) and try again." >&2; return 1; }
    echo "  OK: $(python3 --version 2>&1)"
    echo "  OK: zip found"

    for f in attendance_checker.py assets.csv config.json; do
        if [ ! -f "$TEMPLATES_DIR/$f" ]; then
            echo "  ERROR: templates/$f is missing." >&2
            return 1
        fi
    done
    echo "  OK: all template files present"
}


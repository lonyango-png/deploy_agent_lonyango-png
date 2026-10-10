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

# ---------- Feature 1, step 2: name the project ----------
create_structure() {
    local name
    read -r -p "Enter a name for the project directory: " name
    if [[ ! $name =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "ERROR: The name can contain only letters, numbers, underscores (_), and hyphens (-), and it cannot be empty." >&2
        return 1
    fi
    PROJECT_DIR="attendance_tracker_${name}"

    if [ -e "$PROJECT_DIR" ]; then
        echo "'$PROJECT_DIR' already exists."
        local ans
        read -r -p "Overwrite it? (y/N): " ans
        if [[ $ans =~ ^[Yy]$ ]]; then
            rm -rf "$PROJECT_DIR" || { echo "ERROR: Could not remove '$PROJECT_DIR'." >&2; return 1; }
        else
            echo "Aborting: the existing directory was left untouched." >&2
            return 1
        fi
    fi

    if ! mkdir -p "$PROJECT_DIR/Helpers" "$PROJECT_DIR/reports"; then
        echo "ERROR: Could not create '$PROJECT_DIR'. Check that you have write permission here." >&2
        return 1
    fi
    echo "Created $PROJECT_DIR/{Helpers,reports}"
}

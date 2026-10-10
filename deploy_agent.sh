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

# ---------- Feature 1, step 3: populate files ----------
read_count() {
    local n
    read -r -p "$1 (1-$2): " n
    if [[ ! $n =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt "$2" ]; then
        echo "ERROR: Enter a whole number between 1 and $2." >&2
        return 1
    fi
    echo "$n"
}

populate_files() {
    cp "$TEMPLATES_DIR/attendance_checker.py" "$PROJECT_DIR/" || return 1
    cp "$TEMPLATES_DIR/config.json" "$PROJECT_DIR/Helpers/" || return 1

    local choice n
    echo "How should the roster (assets.csv) be built?"
    echo "  A) Copy from template"
    echo "  B) Generate a fresh roster"
    read -r -p "Choose A or B: " choice

    case "${choice^^}" in
        A)
            local available
            available=$(( $(wc -l < "$TEMPLATES_DIR/assets.csv") - 1 ))
            n=$(read_count "How many students to copy" "$available") || return 1
            head -n $((n + 1)) "$TEMPLATES_DIR/assets.csv" > "$PROJECT_DIR/Helpers/assets.csv" || return 1
            echo "Copied the header row and $n students (each with 4 prior sessions; total_sessions stays at 5)."
            ;;
        B)
            local names=("Alice Johnson" "Bob Smith" "Carol White" "David Brown" "Eve Davis"
                         "Frank Miller" "Grace Wilson" "Henry Moore" "Ivy Taylor" "Jack Anderson")
            local emails=("alice" "bob" "carol" "david" "eve" "frank" "grace" "henry" "ivy" "jack")
            n=$(read_count "How many students to generate" "${#names[@]}") || return 1
            {
                echo "Email,Names,Attendance Count,Absence Count"
                for ((i = 0; i < n; i++)); do
                    echo "${emails[i]}@example.com,${names[i]},0,0"
                done
            } > "$PROJECT_DIR/Helpers/assets.csv" || return 1
            sed -i 's/"total_sessions": *[0-9]*/"total_sessions": 1/' "$PROJECT_DIR/Helpers/config.json" || return 1
            echo "Generated $n students (attendance and absence counts start at 0; total_sessions set to 1)."
            ;;
        *)
            echo "ERROR: Invalid choice. Enter A or B." >&2
            return 1
            ;;
    esac
}

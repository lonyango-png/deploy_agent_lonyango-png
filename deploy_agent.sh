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

# ---------- Feature 1, step 4: set permissions ----------
set_permissions() {
    if ! chmod +x "$PROJECT_DIR/attendance_checker.py" || ! chmod 600 "$PROJECT_DIR/Helpers/config.json"; then
        echo "ERROR: Could not set file permissions." >&2
        return 1
    fi
    echo "Permissions set:"
    echo "  attendance_checker.py -> made executable (chmod +x)"
    echo "  Helpers/config.json   -> restricted to owner read/write only (chmod 600)"
    ls -l "$PROJECT_DIR/attendance_checker.py" "$PROJECT_DIR/Helpers/config.json"
}

# ---------- Feature 1, step 5: update alert thresholds ----------
read_threshold() {   # $1 = label, $2 = default; echoes a validated number (0-100)
    local val
    while true; do
        read -r -p "New $1 threshold (default $2): " val
        if [[ -z $val ]]; then
            echo "ERROR: Please enter a value. This can't be left blank." >&2
        elif [[ ! $val =~ ^[0-9]{1,3}$ ]]; then   # limit to 1-3 digits
            echo "ERROR: '$val' isn't a valid number. Please use 1 to 3 digits only." >&2
        elif [ "$val" -gt 100 ]; then
            echo "ERROR: A percentage can't be higher than 100." >&2
        else
            echo $((10#$val))   # strip leading zeros (08 becomes 8)
            return 0
        fi
    done
}

update_thresholds() {
    local ans warn fail
    read -r -p "Update the attendance alert thresholds? (y/N): " ans
    if [[ ! $ans =~ ^[Yy]$ ]]; then
        echo "No changes made. Keeping the default thresholds (warning 75, failure 50)."
        return 0
    fi

    while true; do
        warn=$(read_threshold "warning" 75)
        fail=$(read_threshold "failure" 50)
        if [ "$warn" -gt "$fail" ]; then
            break
        fi
        echo "ERROR: The warning threshold ($warn) must be higher than the failure threshold ($fail). Let's try again." >&2
    done

    local cfg="$PROJECT_DIR/Helpers/config.json"
    sed -i "s/\"warning\": *[0-9]*/\"warning\": $warn/" "$cfg" || return 1
    sed -i "s/\"failure\": *[0-9]*/\"failure\": $fail/" "$cfg" || return 1
    echo "Thresholds updated: warning is now $warn and failure is now $fail."
}

# ---------- Feature 2: run the application ----------
launch_app() {   # $1 = project directory
    if [ ! -f "$1/attendance_checker.py" ]; then
        echo "ERROR: Couldn't find $1/attendance_checker.py. Please deploy the project first." >&2
        return 1
    fi
    echo "Starting the attendance checker in $1 ..."
    ( cd "$1" && python3 attendance_checker.py )
}

run_application() {
    local name
    read -r -p "Enter the project name to run: " name
    if [[ ! $name =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "ERROR: That isn't a valid project name. Use only letters, numbers, underscores (_), and hyphens (-)." >&2
        return 1
    fi
    if [ ! -d "attendance_tracker_${name}" ]; then
        echo "ERROR: Couldn't find 'attendance_tracker_${name}'. Please deploy it first (option 1)." >&2
        return 1
    fi
    launch_app "attendance_tracker_${name}"
}

# ---------- Feature 3: archive the log files ----------
archive_logs() {
    local name proj stamp type src dest_dir dest
    local archived=0

    read -r -p "Enter the project name whose logs to archive: " name
    if [[ ! $name =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "ERROR: That isn't a valid project name. Use only letters, numbers, underscores (_), and hyphens (-)." >&2
        return 1
    fi

    proj="attendance_tracker_${name}"
    if [ ! -d "$proj" ]; then
        echo "ERROR: Couldn't find '$proj'. Please deploy it first (option 1)." >&2
        return 1
    fi

    stamp=$(date +%Y%m%d_%H%M%S)
    for type in attendance absent; do
        src="$proj/reports/${type}.log"
        if [ ! -f "$src" ]; then
            echo "  Skipped: Couldn't find $src, so there's nothing to archive."
            continue
        fi

        dest_dir="$proj/archives/$type"
        dest="$dest_dir/${type}_${stamp}.log"
        if ! mkdir -p "$dest_dir" || ! mv "$src" "$dest"; then
            echo "  ERROR: Couldn't archive $src. Check your permissions and try again." >&2
            continue
        fi

        echo "  Archived: $src -> $dest"
        archived=$((archived + 1))
    done

    echo "Archive finished. $archived log file(s) were archived."
}

# ---------- Signal handling: Ctrl+C / Ctrl+Z during deploy ----------
CREATED_DIR=""

cleanup() {
    trap - SIGINT SIGTSTP
    echo
    echo "Deployment was interrupted." >&2

    if [ -n "$CREATED_DIR" ] && [ -d "$CREATED_DIR" ]; then
        local zipfile="${CREATED_DIR}_archive.zip"
        if zip -rq "$zipfile" "$CREATED_DIR"; then
            echo "Saved the incomplete project to $zipfile"
            rm -rf "$CREATED_DIR" && echo "Removed the incomplete directory $CREATED_DIR"
        else
            echo "ERROR: Couldn't create the zip file, so '$CREATED_DIR' was kept to avoid losing your work." >&2
        fi
    else
        echo "No project directory had been created yet, so there's nothing to archive."
    fi
    exit 130
}

# ---------- Feature 1 driver ----------
deploy_application() {
    preflight_checks || return 1
    create_structure || return 1
    populate_files   || return 1
    set_permissions  || return 1
    update_thresholds|| return 1
    echo "Deployment complete. Verifying by running the application (step 6)..."
    launch_app "$PROJECT_DIR" || return 1
}

# ---------- Menu ----------
main_menu() {
    while true; do
        echo
        echo "===== Attendance Tracker Deploy Agent ====="
        echo "1) Deploy the application"
        echo "2) Run the application"
        echo "3) Archive log files"
        echo "4) Quit"
        read -r -p "Select an option: " opt
        case "$opt" in
            1) deploy_application ;;
            2) run_application ;;
            3) archive_logs ;;
            4) echo "Goodbye."; exit 0 ;;
            *) echo "Invalid option." ;;
        esac
    done
}

main_menu


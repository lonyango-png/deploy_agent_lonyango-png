# deploy_agent: Attendance Tracker Deployment Script

`deploy_agent.sh` deploys, runs and archives the logs of the Student Attendance Tracker (`attendance_checker.py`). It also handles Ctrl+C and Ctrl+Z during deployment. `attendance_checker.py` is never modified.

## Requirements

- Linux or macOS with bash 4+ (the script uses `${var^^}`; macOS ships bash 3.2 by default, so use Linux or install a newer bash).
- `python3` and `zip` installed. The script checks for both and exits with a clear message if either is missing.
- Run the script from the repository root so `./templates` is found.

## Repository layout

```
deploy_agent_lonyango-png/
├── deploy_agent.sh      # the script (all three features + signal handling)
├── templates/           # the three unmodified source files
│   ├── attendance_checker.py
│   ├── assets.csv
│   └── config.json
├── .gitignore           # keeps generated projects and archive zips out of the repo
└── README.md
```

The `.gitignore` excludes `attendance_tracker_*/` (deployed projects) and `*_archive.zip` (interrupt archives), so generated output is not committed.

## How to run and choose a feature

```
chmod +x deploy_agent.sh
./deploy_agent.sh
```

The script shows an interactive menu and returns to it after each action:

```
1) Deploy the application
2) Run the application
3) Archive log files
4) Quit
```

## Feature 1: Deploy

1. **Pre-flight checks.** `command -v` verifies `python3` and `zip`, `python3 --version` is printed on success, and all three template files must exist. If anything is missing, a clear error is shown and the deploy stops.
2. **Project naming.** The name is read with `read` and validated (letters, numbers, `_` and `-` only, not empty). The script creates `attendance_tracker_<name>/` with `Helpers/` and `reports/`. If the directory already exists, you are asked whether to overwrite it; any answer other than `y` aborts and leaves it untouched. The result of `mkdir` is checked, so a permission error prints a message instead of crashing.
3. **Populate files.** `attendance_checker.py` and `config.json` are copied unmodified from `templates/`. For `Helpers/assets.csv` you choose:
   - **Option A:** copy the header plus N rows from `templates/assets.csv`. N must be a whole number between 1 and the number of rows in the template.
   - **Option B:** generate N fresh rows from built-in arrays of names and emails, with attendance and absence counts at 0 (maximum 10 students).
4. **Permissions.** `chmod +x` on `attendance_checker.py` and `chmod 600` on `Helpers/config.json` (owner only, because it holds the grading thresholds). A confirmation and an `ls -l` listing are printed.
5. **Alert thresholds.** You are asked whether to update them. If yes, `warning` (default 75) and `failure` (default 50) are read and validated before `sed` is used:
   - empty input is rejected
   - non-numeric input is rejected (1 to 3 digits only, which also blocks huge numbers)
   - values above 100 are rejected
   - leading zeros are stripped (`08` becomes `8`) so the JSON stays valid
   - as an extra safeguard (not required by the lab), warning must be higher than failure

   Then `sed -i` edits only the `"warning":` and `"failure":` lines of the deployed `config.json`. The rest of the file is not reformatted or reordered, and the permissions stay `-rw-------`.
6. **Verification.** The deploy ends by running the application (Feature 2). A successful startup confirms that the structure, roster and config work together. This is a real marking session, so it updates the roster counts.

### `total_sessions` and the roster

`total_sessions` must be one more than the prior sessions recorded in the roster.

- **Option A:** the template rows carry 4 prior sessions each, so `total_sessions` stays at 5.
- **Option B:** the fresh roster has no prior sessions, so the script sets `total_sessions` to 1.

`templates/config.json` stays at 5. For Option B, only the deployed copy is changed (with `sed`), so the template is never altered.

## Feature 2: Run

The script asks for the project name, checks that `attendance_tracker_<name>/` exists, then runs the app in a subshell: `( cd attendance_tracker_<name> && python3 attendance_checker.py )`. The subshell keeps the script's own working directory unchanged, and the app finds its relative paths (`Helpers/`, `reports/`). The same step is used for the deploy verification.

## Feature 3: Archive

The script asks for the project name and creates one timestamp with `date +%Y%m%d_%H%M%S`. For each of `reports/attendance.log` and `reports/absent.log`:

- If it exists, it is moved (with `mv`) into its own directory with a timestamped name:

```
attendance_tracker_<name>/archives/
├── attendance/attendance_YYYYMMDD_HHMMSS.log
└── absent/absent_YYYYMMDD_HHMMSS.log
```

- If it does not exist (for example nobody was absent, so no `absent.log` was created), the script prints a "Skipped" message and continues without crashing.

The final paths and the number of archived files are printed. Because the logs are moved, `reports/` is empty again for the next session.

## Signal handling (Ctrl+C and Ctrl+Z)

**Archive trigger:** the trap is set only during the setup steps of Feature 1 (`trap cleanup SIGINT SIGTSTP`). Pressing Ctrl+C (SIGINT) or Ctrl+Z (SIGTSTP) during setup runs the `cleanup` function, which:

1. prints "Deployment was interrupted."
2. zips whatever exists of the project into `attendance_tracker_<name>_archive.zip` (in the repo root) using `zip`
3. deletes the incomplete project directory, but only if the zip succeeded, so no work is lost
4. exits cleanly (exit code 130)

Details:

- The trap is reset (`trap - SIGINT SIGTSTP`) before the Python application launches, so it never applies to a marking session. During marking, Ctrl+C is handled by `attendance_checker.py`, which saves the students already marked.
- Cleanup only touches a directory created by the current run (`CREATED_DIR`). If the project already exists and you interrupt at the overwrite prompt, the existing project is left unchanged and no zip is made.
- If the interrupt happens before any directory is created (for example at the project name prompt), the script reports that there is nothing to archive.

**What the zip contains** depends on when you interrupt. Once the directory exists it holds `attendance_tracker_<name>/`, `Helpers/config.json`, `reports/` and `attendance_checker.py`. `Helpers/assets.csv` is added once the roster step has run.

### How to test the interrupt path

```
./deploy_agent.sh                              # choose 1, enter a name such as trap2
# at "Choose A or B:" press Ctrl+C (repeat in a new run with Ctrl+Z)
ls                                             # zip present, project folder gone
zip -sf attendance_tracker_trap2_archive.zip   # list the zip contents
```

## Testing summary

Tested on Linux with bash and Python 3.8.10.

| Area | Test | Result |
|---|---|---|
| Structure | Deploy with Option A (3 students); check `Helpers/`, `reports/`, files, permissions | `-rwxr-xr-x` on the `.py`, `-rw-------` on `config.json` |
| Roster | Option B with 2 students | counts 0,0; `total_sessions` = 1 in the deployed copy, template still 5 |
| Existing directory | Re-deploy the same name, answer `n` and `y` | `n` aborts untouched; `y` overwrites |
| Bad input | Empty or invalid name, invalid A/B choice, count `abc` / `0` / `99` | clear error, back to menu |
| Thresholds | Empty, `abc`, `150`, `08`, warning below failure, then `80`/`40` | rejected or normalised; `config.json` updated on its original lines |
| Run | Option 2 on an existing and on a missing project | app runs; missing project gives an error |
| Archive | Option 3 after a run; again with no logs; with no `absent.log` | files archived with timestamps; missing logs skipped without a crash |
| Ctrl+C at name prompt | Interrupt before any directory exists | "nothing to archive", no zip |
| Ctrl+C at A/B prompt | Interrupt after directory creation | zip created, directory removed |
| Ctrl+Z at A/B prompt | Same point as above | same result as Ctrl+C |
| Ctrl+C at overwrite prompt | Interrupt with an existing project | existing project untouched, no zip |
| Ctrl+C at count and threshold prompts | Interrupt inside `$( ... )` prompts | zip created, directory removed |
| Ctrl+C during marking | Interrupt inside the Python app | handled by the app, no zip, back to menu |

## Git workflow

Development used feature branches, merged into `main` with merge commits: `feature-1-deploy` (Feature 1 steps 1 to 6 and Feature 2), `feature-3-archive`, `feature-signal-trap` and `docs-readme`. Each step was committed separately with a descriptive message.

## Video walkthrough

https://drive.google.com/file/d/13ao9pThaU5LZNcakCK02rYRSAo6e7te9/view?usp=sharing

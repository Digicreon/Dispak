#!/usr/bin/env bash

# Tests of the 'dpk install' --no-* options: an option given without a value must be
# detected (presence test on DPK_OPT) and disable the corresponding installation step.
# The real functions of the install rule are used, with stubbed system commands.

. "$(dirname "$0")/lib.sh"

# stubs (no system command is really executed)
declare -A DPK_OPT
ansi() { :; }
abort() { echo "ABORT: $*"; exit 1; }
warn() { echo "WARN: $*"; }
crontab() { echo "[stub crontab $*]"; }
sudo() { echo "[stub sudo $*]"; }

# load the install rule, and create a fake repository with a crontab file
. "$(dirname "$DPK")/rules/03-install.sh"
create_test_dir
GIT_REPO_PATH="$TEST_DIR/repo"
mkdir -p "$GIT_REPO_PATH/etc"
echo "0 0 * * * true" > "$GIT_REPO_PATH/etc/crontab"

echo "== option without a value (documented usage) =="
DPK_OPT=()
DPK_OPT["no-crontab"]=""
OUT="$(_install_crontab)"
[ -z "$OUT" ]
check $? "crontab installation skipped"

echo "== option with a value =="
DPK_OPT=()
DPK_OPT["no-crontab"]="1"
OUT="$(_install_crontab)"
[ -z "$OUT" ]
check $? "crontab installation skipped"

echo "== no option (counter-test) =="
DPK_OPT=()
OUT="$(_install_crontab)"
echo "$OUT" | grep -q "stub crontab"
check $? "crontab installation performed"

test_end

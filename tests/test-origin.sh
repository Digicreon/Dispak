#!/usr/bin/env bash

# Tests of the 'dpk origin' command.

. "$(dirname "$0")/lib.sh"

create_test_repos

echo "== remote origin URL =="
OUT="$("$DPK" origin 2>&1)"
check $? "the command succeeds"
echo "$OUT" | grep -qF "$REMOTE"
check $? "the remote origin URL is displayed"

echo "== error case =="
cd "$TEST_DIR"
"$DPK" origin > /dev/null 2>&1
[ $? -eq 31 ]
check $? "refused outside a git repository (exit code 31)"

test_end

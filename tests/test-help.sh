#!/usr/bin/env bash

# Tests of the 'dpk help' command and of the command-line errors handling.

. "$(dirname "$0")/lib.sh"

create_test_dir
cd "$TEST_DIR"

echo "== general help (outside a git repository) =="
OUT="$("$DPK" help 2>&1)"
check $? "the command succeeds"
MISSING=0
for RULE in branch tags pkg install config origin; do
	echo "$OUT" | grep -q "$RULE" || MISSING=1
done
[ $MISSING -eq 0 ]
check $? "all the rules are listed"

echo "== help of a single rule =="
OUT="$("$DPK" help branch 2>&1)"
check $? "the command succeeds"
echo "$OUT" | grep -q -- "--parent" && echo "$OUT" | grep -q -- "--rebase"
check $? "the rule's options are documented"

echo "== command-line errors =="
"$DPK" nonexistentcommand > /dev/null 2>&1
[ $? -ne 0 ]
check $? "unknown command refused"
OUT="$("$DPK" origin --badoption 2>&1)"
[ $? -ne 0 ] && echo "$OUT" | grep -q "Extraneous parameter"
check $? "extraneous parameter refused"

test_end

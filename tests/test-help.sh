#!/usr/bin/env bash

# Tests of the 'dpk help' command, of the command-line errors handling, and of the
# custom rules loading.

. "$(dirname "$0")/lib.sh"

create_test_repos
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
[ $? -eq 11 ]
check $? "unknown command refused (exit code 11)"
OUT="$("$DPK" origin --badoption 2>&1)"
[ $? -eq 13 ] && echo "$OUT" | grep -q "Extraneous parameter"
check $? "extraneous parameter refused (exit code 13)"
OUT="$("$DPK" origin -h 2>&1)"
[ $? -eq 13 ] && echo "$OUT" | grep -q "Bad command line option '-h'"
check $? "unknown short option refused (exit code 13)"

echo "== custom rule =="
cd "$WORK"
mkdir -p etc/dispak-rules
cat > etc/dispak-rules/dummy.sh <<'EOF'
#!/usr/bin/env bash
RULE_NAME="dummy"
RULE_SECTION="Test"
RULE_MANDATORY_PARAMS="target"
RULE_OPTIONAL_PARAMS=""
rule_help_dummy() {
	:
}
rule_exec_dummy() {
	echo "dummy executed with target '${DPK_OPT["target"]}'"
}
EOF
OUT="$("$DPK" dummy --target=x 2>&1)"
[ $? -eq 0 ] && echo "$OUT" | grep -q "dummy executed with target 'x'"
check $? "custom rule loaded and executed"
"$DPK" dummy > /dev/null 2>&1
[ $? -eq 12 ]
check $? "missing mandatory parameter refused (exit code 12)"

test_end

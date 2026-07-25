#!/usr/bin/env bash

# Tests of the 'dpk tags' command: condensed list, full list with annotations, and
# error case when no tag exists.

. "$(dirname "$0")/lib.sh"

create_test_repos

echo "== error case: no tag =="
"$DPK" tags > /dev/null 2>&1
[ $? -eq 35 ]
check $? "refused when no tag exists (exit code 35)"

# create some tags (0.1.0, 0.1.1, 0.2.0) and one commit after the last tag
git tag -a 0.1.0 -m "first unstable version"
echo "a" >> f1.txt
git commit -qam "second commit"
git tag -a 0.1.1 -m "revision annotation message"
echo "b" >> f1.txt
git commit -qam "third commit"
git tag -a 0.2.0 -m "first stable version"
echo "c" >> f1.txt
git commit -qam "fourth commit"
git push -q --tags origin main

echo "== condensed list =="
OUT="$("$DPK" tags 2>&1)"
check $? "the command succeeds"
echo "$OUT" | grep -q "0\.1\.0" && echo "$OUT" | grep -q "0\.2\.0"
check $? "minor versions displayed"
! echo "$OUT" | grep -q "0\.1\.1"
check $? "in-between revisions hidden"
echo "$OUT" | grep -q "1 commit since last tag."
check $? "commits count since the last tag"

echo "== full list =="
OUT="$("$DPK" tags --all 2>&1)"
check $? "the command succeeds"
echo "$OUT" | grep -q "0\.1\.1"
check $? "in-between revisions displayed"
echo "$OUT" | grep -q "revision annotation message"
check $? "tag annotations displayed"

test_end

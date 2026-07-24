#!/usr/bin/env bash

# Tests of the 'dpk branch --parent' command: parent branch detection, ahead/behind
# counts, and error cases.

. "$(dirname "$0")/lib.sh"

create_test_repos
# create a feature branch from main, and a sub-branch from the feature branch
create_branch feature feat.txt "feature content"
git checkout -qb subfeature feature
echo "sub content" > sub.txt
git add sub.txt
git commit -qm "change in subfeature"
git push -qu origin subfeature
# remotely advance the main branch
cd "$WORK2"
git checkout -q main
git pull -q
echo "advance" > adv.txt
git add adv.txt
git commit -qm "main advance"
git push -q origin main
cd "$WORK"

echo "== parent of a given branch =="
OUT="$("$DPK" branch --parent=subfeature 2>&1)"
check $? "the command succeeds"
echo "$OUT" | grep -a "Created from:" | grep -qE " feature$"
check $? "parent of subfeature = feature"

echo "== parent of the current branch =="
git checkout -q feature
OUT="$("$DPK" branch --parent 2>&1)"
check $? "the command succeeds"
echo "$OUT" | grep -a "Created from:" | grep -qE " main$"
check $? "parent of feature = main"
echo "$OUT" | grep -a "Ahead:" | grep -q "1 commit"
check $? "1 commit ahead"
echo "$OUT" | grep -a "Behind:" | grep -q "1 commit"
check $? "1 commit behind"

echo "== error cases =="
"$DPK" branch --parent=main > /dev/null 2>&1
[ $? -ne 0 ]
check $? "refused on the main branch"
"$DPK" branch --parent=nonexistent > /dev/null 2>&1
[ $? -ne 0 ]
check $? "refused on an unknown branch"

test_end

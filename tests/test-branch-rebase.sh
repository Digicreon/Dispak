#!/usr/bin/env bash

# Tests of the 'dpk branch --rebase' command: nominal rebase, conflict and resume,
# concurrent push and automatic replay, rebase not started by Dispak, guard against
# other commands during a rebase, and context file cleanup.

. "$(dirname "$0")/lib.sh"

create_test_repos
# create the branches used by the scenarios (each one changes its own file)
create_branch nominal n.txt "new file"
create_branch confl f2.txt "branch version 2"
create_branch confl2 f3.txt "branch version 3"
create_branch confl3 f4.txt "branch version 4"
git checkout -q main
# remotely advance the main branch, with changes conflicting with the confl* branches
cd "$WORK2"
git checkout -q main
git pull -q
for I in 1 2 3 4; do
	echo "main version $I" > "f$I.txt"
done
git commit -qam "main advances"
git push -q origin main
cd "$WORK"

echo "== nominal rebase =="
git checkout -q nominal
"$DPK" branch --rebase > /dev/null 2>&1
check $? "the command succeeds"
[ "$(git rev-parse nominal)" = "$(git rev-parse origin/nominal)" ]
check $? "local branch = remote branch"
git merge-base --is-ancestor origin/main nominal
check $? "rebased on the last main revision"
[ ! -f .git/dispak-rebase ]
check $? "no context file left"

echo "== conflict, then resume =="
git checkout -q confl
"$DPK" branch --rebase > /dev/null 2>&1
[ $? -ne 0 ] && [ -f .git/dispak-rebase ]
check $? "abort on conflict, context file created"
echo "solved 2" > f2.txt
git add f2.txt
"$DPK" branch --rebase > /dev/null 2>&1
check $? "the resume succeeds"
[ "$(git rev-parse confl)" = "$(git rev-parse origin/confl)" ] && [ ! -f .git/dispak-rebase ]
check $? "pushed, context file deleted"

echo "== concurrent push during a conflict, then automatic replay =="
git checkout -q confl2
"$DPK" branch --rebase > /dev/null 2>&1
cd "$WORK2"
git fetch -q
git checkout -q confl2 2> /dev/null
echo "extra" > x.txt
git add x.txt
git commit -qm "concurrent commit"
git push -q origin confl2
cd "$WORK"
echo "solved 3" > f3.txt
git add f3.txt
OUT="$("$DPK" branch --rebase 2>&1)"
echo "$OUT" | grep -aq "stale info"
check $? "resume push rejected (stale info)"
echo "$OUT" | grep -aq "replaying the rebase"
check $? "automatic replay triggered"
echo "solved 3" > f3.txt
git add f3.txt
"$DPK" branch --rebase > /dev/null 2>&1
check $? "the second resume succeeds"
git log --oneline confl2 | grep -q "concurrent commit"
check $? "the concurrent commit is preserved"
[ "$(git rev-parse confl2)" = "$(git rev-parse origin/confl2)" ] && [ ! -f .git/dispak-rebase ]
check $? "pushed, context file deleted"

echo "== rebase not started by Dispak =="
git checkout -q confl3
git rebase main > /dev/null 2>&1
OUT="$("$DPK" branch --rebase 2>&1)"
echo "$OUT" | grep -aq "not started by Dispak"
check $? "adoption refused"
git rebase --abort

echo "== guard and context file cleanup =="
echo "confl main abc" > .git/dispak-rebase
"$DPK" branch --list > /dev/null 2>&1
[ ! -f .git/dispak-rebase ]
check $? "leftover context file removed in a stable state"
"$DPK" branch --rebase > /dev/null 2>&1
OUT="$("$DPK" branch --list 2>&1)"
echo "$OUT" | grep -aq "A rebase is in progress"
check $? "other commands blocked during a conflict"
[ -f .git/dispak-rebase ]
check $? "context file kept during the conflict"
echo "solved 4" > f4.txt
git add f4.txt
"$DPK" branch --rebase > /dev/null 2>&1
check $? "the final resume succeeds"
[ ! -f .git/dispak-rebase ]
check $? "context file deleted"

test_end

#!/usr/bin/env bash

# Tests of the 'dpk branch' commands not covered by the other test scripts:
# --create (with --from and --tag), --list, --graph, --merge, --backport, --rename,
# --remove and --prune.

. "$(dirname "$0")/lib.sh"

create_test_repos

echo "== create a branch =="
"$DPK" branch --create=feat1 > /dev/null 2>&1
check $? "the command succeeds"
[ "$(git rev-parse --abbrev-ref HEAD)" = "feat1" ]
check $? "moved to the new branch"
[ "$(git ls-remote --heads "$REMOTE" feat1 | wc -l)" -eq 1 ]
check $? "the branch was pushed"
# commit a change on the branch (used by the merge test below)
echo "feat1 content" > fa.txt
git add fa.txt
git commit -qm "feat1 commit"
git push -q origin feat1

echo "== create a branch from another branch =="
"$DPK" branch --create=sub1 --from=feat1 > /dev/null 2>&1
check $? "the command succeeds"
[ "$(git rev-parse sub1)" = "$(git rev-parse origin/feat1)" ]
check $? "created from the source branch's last revision"

echo "== create a branch from a tag =="
git checkout -q main
git tag -a 0.1.0 -m "first version"
git push -q origin 0.1.0
"$DPK" branch --create=fromtag --tag=0.1.0 > /dev/null 2>&1
check $? "the command succeeds"
[ "$(git rev-parse fromtag)" = "$(git rev-parse "0.1.0^{commit}")" ]
check $? "created from the tag's revision"

echo "== create error cases =="
"$DPK" branch --create=feat1 > /dev/null 2>&1
[ $? -ne 0 ]
check $? "existing branch name refused"
"$DPK" branch --create=x1 --from=feat1 --tag=0.1.0 > /dev/null 2>&1
[ $? -ne 0 ]
check $? "--from and --tag together refused"
"$DPK" branch --create=x2 --from=nonexistent > /dev/null 2>&1
[ $? -ne 0 ]
check $? "nonexistent source branch refused"

echo "== list branches =="
git checkout -q main
git checkout -qb localonly
git checkout -q main
OUT="$("$DPK" branch --list 2>&1)"
check $? "the command succeeds"
echo "$OUT" | grep -q "localonly"
check $? "local-only branch listed"
echo "$OUT" | grep -q "feat1"
check $? "remote branch listed"

echo "== branches graph =="
OUT="$("$DPK" branch --graph 2>&1)"
check $? "the command succeeds"
[ -n "$OUT" ]
check $? "the graph is displayed"

echo "== merge a branch =="
git checkout -q feat1
"$DPK" branch --merge > /dev/null 2>&1
check $? "the command succeeds"
git merge-base --is-ancestor feat1 origin/main
check $? "the branch was merged on the main branch"
[ "$(git rev-parse --abbrev-ref HEAD)" = "feat1" ]
check $? "moved back to the branch"
"$DPK" branch --merge=nonexistent > /dev/null 2>&1
[ $? -ne 0 ]
check $? "nonexistent destination branch refused"

echo "== backport =="
git checkout -q sub1
"$DPK" branch --backport > /dev/null 2>&1
check $? "the command succeeds"
git merge-base --is-ancestor origin/main sub1
check $? "the main branch was merged on the current branch"

echo "== rename a branch =="
"$DPK" branch --rename=renamed1 > /dev/null 2>&1
check $? "the command succeeds"
git rev-parse --verify --quiet renamed1 > /dev/null
check $? "the local branch was renamed"
[ "$(git ls-remote --heads "$REMOTE" sub1 | wc -l)" -eq 0 ] && [ "$(git ls-remote --heads "$REMOTE" renamed1 | wc -l)" -eq 1 ]
check $? "the remote branch was renamed"
"$DPK" branch --rename=feat1 > /dev/null 2>&1
[ $? -ne 0 ]
check $? "renaming to an existing name refused"

echo "== remove a branch =="
"$DPK" branch --remove=renamed1 > /dev/null 2>&1
check $? "the command succeeds"
! git rev-parse --verify --quiet renamed1 > /dev/null
check $? "the local branch was removed"
[ "$(git ls-remote --heads "$REMOTE" renamed1 | wc -l)" -eq 0 ]
check $? "the remote branch was removed"
"$DPK" branch --remove=main > /dev/null 2>&1
[ $? -ne 0 ]
check $? "removing the main branch refused"
"$DPK" branch --remove=nonexistent > /dev/null 2>&1
[ $? -ne 0 ]
check $? "removing a nonexistent branch refused"

echo "== prune local-only branches =="
git checkout -q main
git checkout -qb lp1
git checkout -qb lp2
echo "x" > lp.txt
git add lp.txt
git commit -qm "lp2 commit"
git checkout -q main
"$DPK" branch --prune=feat1 > /dev/null 2>&1
[ $? -ne 0 ]
check $? "pruning a remote branch refused"
git checkout -q lp2
"$DPK" branch --prune > /dev/null 2>&1
[ $? -ne 0 ]
check $? "refused while on a local-only branch"
git checkout -q main
"$DPK" branch --prune=lp1 > /dev/null 2>&1
check $? "prune of a given branch succeeds"
! git rev-parse --verify --quiet lp1 > /dev/null && git rev-parse --verify --quiet lp2 > /dev/null
check $? "only the given branch was removed"
echo "y" | "$DPK" branch --prune > /dev/null 2>&1
check $? "prune of all local-only branches succeeds"
! git rev-parse --verify --quiet localonly > /dev/null && ! git rev-parse --verify --quiet lp2 > /dev/null
check $? "all local-only branches removed (with confirmation for the unmerged one)"

echo "== exit codes of the git checks =="
"$DPK" branch --merge > /dev/null 2>&1
[ $? -eq 32 ]
check $? "merge refused on the main branch (exit code 32)"
"$DPK" branch --create=xtag --tag=9.9.9 > /dev/null 2>&1
[ $? -eq 35 ]
check $? "creation from a nonexistent tag refused (exit code 35)"
git checkout -q feat1
echo "dirty" >> fa.txt
echo "n" | "$DPK" branch --merge > /dev/null 2>&1
[ $? -eq 33 ]
check $? "merge refused on a dirty repository (exit code 33)"
git checkout -q -- fa.txt
echo "unpushed" >> fa.txt
git commit -qam "unpushed commit"
"$DPK" branch --merge > /dev/null 2>&1
[ $? -eq 34 ]
check $? "merge refused with unpushed commits (exit code 34)"
git reset -q --hard origin/feat1

test_end

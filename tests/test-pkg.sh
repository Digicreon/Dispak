#!/usr/bin/env bash

# Tests of the 'dpk pkg' command: tag creation and push, database migration file
# rotation, and error cases. The EDITOR variable is set to 'true' so the annotation
# message editor is skipped.

. "$(dirname "$0")/lib.sh"

create_test_repos
# create a database migration file
mkdir -p etc/database/migrations
echo "ALTER TABLE foo;" > etc/database/migrations/current
git add etc
git commit -qm "add migration file"
git push -q origin main

echo "== first tag =="
EDITOR=true "$DPK" pkg --tag=0.1.0 > /dev/null 2>&1
check $? "the command succeeds"
git rev-parse --verify --quiet "0.1.0" > /dev/null
check $? "the tag exists locally"
[ "$(git ls-remote --tags "$REMOTE" | grep -c "0\.1\.0")" -ge 1 ]
check $? "the tag was pushed"
[ -f etc/database/migrations/0.1.0 ] && [ -f etc/database/migrations/current ] && [ ! -s etc/database/migrations/current ]
check $? "migration file rotated (renamed with the tag, new empty 'current' file)"

echo "== error case: no commit since the last tag =="
EDITOR=true "$DPK" pkg --tag=0.1.1 > /dev/null 2>&1
[ $? -eq 30 ]
check $? "refused when there is no new commit (exit code 30)"

echo "== second tag =="
echo "more" >> f1.txt
git commit -qam "new commit"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.1.1 > /dev/null 2>&1
check $? "the command succeeds"
git rev-parse --verify --quiet "0.1.1" > /dev/null
check $? "the tag exists locally"

echo "== error case: tag numbers jump =="
echo "even more" >> f1.txt
git commit -qam "another commit"
git push -q origin main
echo "z" | EDITOR=true "$DPK" pkg --tag=0.1.5 > /dev/null 2>&1
[ $? -eq 14 ]
check $? "invalid tag number refused (exit code 14)"

echo "== check URL in error =="
echo 'CONF_PKG_CHECK_URL="http://localhost:1/"' > etc/dispak.conf
git add etc/dispak.conf
git commit -qm "add dispak.conf with a check URL"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.1.2 > /dev/null 2>&1
[ $? -eq 22 ]
check $? "refused when the check URL fails (exit code 22)"

echo "== failing pre-packaging script =="
printf '#!/bin/sh\nexit 1\n' > etc/fail.sh
chmod +x etc/fail.sh
printf 'CONF_PKG_SCRIPTS_PRE="./etc/fail.sh"\n' > etc/dispak.conf
git add etc
git commit -qm "failing pre-packaging script"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.1.2 > /dev/null 2>&1
[ $? -eq 51 ]
check $? "refused when a pre-packaging script fails (exit code 51)"
! git rev-parse --verify --quiet "0.1.2" > /dev/null
check $? "the tag was not created"

echo "== failing post-packaging script =="
printf 'CONF_PKG_SCRIPTS_POST="./etc/fail.sh"\n' > etc/dispak.conf
git commit -qam "failing post-packaging script"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.1.2 > /dev/null 2>&1
[ $? -eq 52 ]
check $? "post-packaging script failure reported (exit code 52)"
git rev-parse --verify --quiet "0.1.2" > /dev/null
check $? "the tag was created before the post-packaging script"

test_end

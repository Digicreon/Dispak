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

# ########## Amazon S3 upload ##########
# fake 'aws' program, which logs its calls (and fails if the AWS_FAIL variable is set to 1)
mkdir -p "$TEST_DIR/bin"
export AWS_LOG="$TEST_DIR/aws.log"
printf '#!/bin/sh\necho "$*" >> "$AWS_LOG"\n[ "$AWS_FAIL" != "1" ]\n' > "$TEST_DIR/bin/aws"
chmod +x "$TEST_DIR/bin/aws"
export PATH="$TEST_DIR/bin:$PATH"
touch "$AWS_LOG"
# post-S3 upload script, which logs the tag it receives
S3_SCRIPT_LOG="$TEST_DIR/s3-script.log"
printf '#!/bin/sh\necho "$2" >> "%s"\n' "$S3_SCRIPT_LOG" > "$TEST_DIR/s3.sh"
chmod +x "$TEST_DIR/s3.sh"
touch "$S3_SCRIPT_LOG"
# static files, and a concatenated file generated from a source outside of the static directory
mkdir -p static src
echo "body {}" > static/style.css
echo "p {}" > src/extra.css
# write_s3_conf()
# Write and commit the dispak configuration file, with the given S3 behaviour.
write_s3_conf() {
	cat > etc/dispak.conf << EOF
CONF_PKG_S3["bucket"]="static"
CONF_PKG_S3_BEHAVIOUR="$1"
CONF_PKG_SCRIPTS_S3="$TEST_DIR/s3.sh"
CONF_PKG_CONCAT["static/all.css"]="src/extra.css"
EOF
	git add -A
	git commit -qm "S3 configuration ($1)"
	git push -q origin main
}
# s3_sent()
# Tell if files were sent to S3 for the given tag (and if the post-S3 script was executed).
s3_sent() {
	grep -q "s3://bucket/$1" "$AWS_LOG" && grep -qx "$1" "$S3_SCRIPT_LOG"
}
# s3_not_sent()
# Tell if no file was sent to S3 for the given tag (and if the post-S3 script was not executed).
s3_not_sent() {
	! grep -q "s3://bucket/$1" "$AWS_LOG" && ! grep -qx "$1" "$S3_SCRIPT_LOG"
}

echo "== S3 'modified' behaviour: first upload =="
write_s3_conf modified
EDITOR=true "$DPK" pkg --tag=0.2.0 > /dev/null 2>&1
check $? "the command succeeds"
s3_sent 0.2.0
check $? "files sent to S3 and post-S3 script executed"
[ "$(git show 0.2.0:etc/s3_upload_last_tag)" = "0.2.0" ]
check $? "the S3 version file is part of the tag"
git fetch -q origin && [ "$(git show origin/main:etc/s3_upload_last_tag)" = "0.2.0" ]
check $? "the S3 version file was pushed"
[ ! -e static/all.css ]
check $? "the concatenated file was removed"

echo "== S3 'modified' behaviour: no modification =="
echo "other" >> f1.txt
git commit -qam "change outside of static files"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.2.1 > /dev/null 2>&1
check $? "the command succeeds"
s3_not_sent 0.2.1
check $? "no file sent to S3, post-S3 script not executed"
[ "$(cat etc/s3_upload_last_tag)" = "0.2.0" ]
check $? "the S3 version file is unchanged"

echo "== S3 'modified' behaviour: forced upload =="
echo "other" >> f1.txt
git commit -qam "change outside of static files"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.2.2 --s3-force > /dev/null 2>&1
check $? "the command succeeds"
s3_sent 0.2.2
check $? "files sent to S3 with the --s3-force option"

echo "== S3 'modified' behaviour: static file modified =="
echo "h1 {}" >> static/style.css
git commit -qam "change in static files"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.2.3 > /dev/null 2>&1
check $? "the command succeeds"
s3_sent 0.2.3
check $? "files sent to S3"
[ "$(git show 0.2.3:etc/s3_upload_last_tag)" = "0.2.3" ]
check $? "the S3 version file was updated"

echo "== S3 'modified' behaviour: concatenation source modified =="
echo "h2 {}" >> src/extra.css
git commit -qam "change in a concatenation source file"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.2.4 > /dev/null 2>&1
check $? "the command succeeds"
s3_sent 0.2.4
check $? "files sent to S3"

echo "== S3 'modified' behaviour: unstable tag =="
echo "h3 {}" >> static/style.css
git commit -qam "change in static files"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.3.0 > /dev/null 2>&1
check $? "the command succeeds"
s3_not_sent 0.3.0
check $? "no file sent to S3 for an unstable tag"
[ "$(cat etc/s3_upload_last_tag)" = "0.2.4" ]
check $? "the S3 version file is unchanged"

echo "== S3 'always' behaviour =="
write_s3_conf always
EDITOR=true "$DPK" pkg --tag=0.4.0 > /dev/null 2>&1
check $? "the command succeeds"
s3_sent 0.4.0
check $? "files sent to S3"
echo "other" >> f1.txt
git commit -qam "change outside of static files"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.4.1 > /dev/null 2>&1
check $? "the command succeeds"
s3_sent 0.4.1
check $? "files sent to S3 even without modification"

echo "== error case: unknown S3 behaviour =="
write_s3_conf foo
EDITOR=true "$DPK" pkg --tag=0.4.2 > /dev/null 2>&1
[ $? -eq 20 ]
check $? "refused with an unknown S3 behaviour (exit code 20)"
! git rev-parse --verify --quiet "0.4.2" > /dev/null
check $? "the tag was not created"

echo "== error case: S3 upload failure =="
write_s3_conf always
AWS_FAIL=1 EDITOR=true "$DPK" pkg --tag=0.4.2 > /dev/null 2>&1
[ $? -eq 23 ]
check $? "S3 upload failure reported (exit code 23)"
git rev-parse --verify --quiet "0.4.2" > /dev/null
check $? "the tag was created before the upload"
! grep -qx "0.4.2" "$S3_SCRIPT_LOG"
check $? "the post-S3 script was not executed"
[ ! -e static/all.css ]
check $? "the concatenated file was removed"

echo "== error case: failing post-S3 upload script =="
sed -i "s#^CONF_PKG_SCRIPTS_S3=.*#CONF_PKG_SCRIPTS_S3=\"./etc/fail.sh\"#" etc/dispak.conf
git commit -qam "failing post-S3 upload script"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.4.3 > /dev/null 2>&1
[ $? -eq 58 ]
check $? "post-S3 upload script failure reported (exit code 58)"

echo "== S3 compression =="
# s3_gzipped()
# Tell if the given file was sent compressed to S3, under its original name.
s3_gzipped() {
	grep -F "s3://bucket/0.4.4/$1 " "$AWS_LOG" | grep -q -- "--content-encoding gzip"
}
# s3_raw()
# Tell if the given file was sent uncompressed to S3.
s3_raw() {
	grep -F "s3://bucket/0.4.4/$1 " "$AWS_LOG" | grep -qv -- "--content-encoding gzip"
}
# Javascript module (seen as 'application/javascript' by the 'file' program, not as plain text)
echo 'import { foo } from "./foo.js";' > static/app.js
for I in $(seq 1 60); do
	echo "export const value$I = foo($I);" >> static/app.js
	echo ".class$I { color: red; }" >> static/big.css
done
# Javascript file with an already compressed version
cp static/app.js static/pre.js
gzip -k static/pre.js
# files around the minimum size
head -c 1024 static/big.css > static/limit.css
head -c 1023 static/big.css > static/small.css
# binary file
head -c 8192 /dev/urandom > static/data.bin
write_s3_conf always
echo 'CONF_PKG_S3_COMPRESS=1' >> etc/dispak.conf
git commit -qam "S3 compression"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.4.4 > /dev/null 2>&1
check $? "the command succeeds"
s3_gzipped app.js
check $? "Javascript file compressed"
s3_gzipped big.css
check $? "CSS file compressed"
s3_gzipped limit.css
check $? "1024 bytes file compressed"
s3_raw small.css
check $? "1023 bytes file not compressed"
s3_raw data.bin
check $? "binary file not compressed"
s3_gzipped pre.js && [ "$(grep -cF "s3://bucket/0.4.4/pre.js" "$AWS_LOG")" -eq 1 ] && grep -q "^s3 cp pre\.js\.gz " "$AWS_LOG"
check $? "already compressed Javascript file sent in place of the original one"
[ "$(git status --porcelain)" = "" ]
check $? "no temporary file left in the repository"

test_end

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
# static directory which can't be entered (not relevant for the root user)
if [ "$(id -u)" -ne 0 ]; then
	mkdir "$TEST_DIR/locked"
	chmod 000 "$TEST_DIR/locked"
	sed -i "s#^CONF_PKG_S3\[.*#CONF_PKG_S3[\"bucket\"]=\"$TEST_DIR/locked\"#" etc/dispak.conf
	git commit -qam "locked static directory"
	git push -q origin main
	EDITOR=true "$DPK" pkg --tag=0.4.5 > /dev/null 2>&1
	[ $? -eq 23 ]
	check $? "failure reported when the static directory can't be entered (exit code 23)"
	! grep -q "s3://bucket/0.4.5" "$AWS_LOG"
	check $? "no file sent from another directory"
	chmod 700 "$TEST_DIR/locked"
else
	git commit -q --allow-empty -m "root user"
	git tag 0.4.5
fi

echo "== S3 minification =="
# fake 'aws' program, which also keeps a copy of the sent files
export AWS_COPY="$TEST_DIR/aws-copy"
cat > "$TEST_DIR/bin/aws" << 'EOF'
#!/bin/bash
echo "$*" >> "$AWS_LOG"
[ "$AWS_FAIL" = "1" ] && exit 1
DEST="$AWS_COPY/${4#s3://bucket/}"
mkdir -p "$(dirname "$DEST")"
cp -R "$3" "$DEST"
EOF
# fake 'minify' program, which logs its working directory (fails if the file contains "BAD", after
# having written something, like the real program)
export MINIFY_LOG="$TEST_DIR/minify.log"
cat > "$TEST_DIR/bin/minify" << 'EOF'
#!/bin/bash
[ "$1" = "--version" ] && echo "minify v${MINIFY_VERSION:-2.25.0}" && exit 0
pwd >> "$MINIFY_LOG"
echo "MINIFIED"
grep -q "BAD" "$1" && echo "ERROR: cannot minify" >&2 && exit 1
cat "$1"
EOF
chmod +x "$TEST_DIR/bin/aws" "$TEST_DIR/bin/minify"
# minified()
# Tell if the given file was sent minified (only once) to S3.
# @param	string	Tag.
# @param	string	Path to the file.
minified() {
	[ "$(head -1 "$AWS_COPY/$1/$2")" = "MINIFIED" ] && [ "$(grep -c "MINIFIED" "$AWS_COPY/$1/$2")" -eq 1 ]
}
# unchanged()
# Tell if the given file was sent unchanged to S3.
# @param	string	Tag.
# @param	string	Path to the file.
unchanged() {
	cmp -s "static/$2" "$AWS_COPY/$1/$2"
}
# write_minify_conf()
# Write and commit the dispak configuration file.
# @param	string	Value of the CONF_PKG_S3_MINIFY variable.
# @param	int	Value of the CONF_PKG_S3_COMPRESS variable.
write_minify_conf() {
	write_s3_conf always
	{
		echo "CONF_PKG_S3_MINIFY=\"$1\""
		echo "CONF_PKG_S3_COMPRESS=\"$2\""
		echo 'CONF_PKG_MINIFY["static/generated.css"]="src/extra.css"'
		echo 'CONF_PKG_MINIFY["static/gen/bundle.js"]="src/one.js src/two.js"'
	} >> etc/dispak.conf
	git commit -qam "S3 minification ($1, $2)"
	git push -q origin main
}
printf '(function() { one })()' > src/one.js
printf '(function() { two })() // end' > src/two.js
mkdir -p "static/sub dir"
cp static/app.js "static/sub dir/my app.mjs"
echo "{}" > static/data.json
echo "<svg/>" > static/icon.svg
echo "<p>" > static/page.html
echo "text" > static/notes.txt
echo "lib" > static/lib.min.js
echo "BAD" > static/bad.js
ln -s style.css static/link.css
mkdir static/theme.min.d static/readonly
echo "x" > static/theme.min.d/x.js
echo "y" > static/readonly/y.js
chmod 555 static/readonly
# without compression
write_minify_conf 1 0
MINIFY_OUTPUT="$(EDITOR=true "$DPK" pkg --tag=0.4.6 2>&1)"
check $? "the command succeeds"
[ "$(grep "s3://bucket/0.4.6" "$AWS_LOG" | grep -c "^s3 sync ")" -eq 1 ] && ! grep -q "^s3 cp .*s3://bucket/0.4.6" "$AWS_LOG"
check $? "files sent in bulk"
minified 0.4.6 app.js && minified 0.4.6 "sub dir/my app.mjs" && minified 0.4.6 style.css && minified 0.4.6 data.json
check $? "js, mjs, css and json files minified"
minified 0.4.6 theme.min.d/x.js
check $? "file minified in a directory whose name contains '.min.'"
minified 0.4.6 readonly/y.js
check $? "file minified in a read-only directory"
minified 0.4.6 all.css
check $? "concatenated file minified"
minified 0.4.6 generated.css
check $? "file generated by CONF_PKG_MINIFY not minified twice"
minified 0.4.6 gen/bundle.js && tail -n +2 "$AWS_COPY/0.4.6/gen/bundle.js" | cmp -s - <(cat src/one.js; printf '\n;\n'; cat src/two.js; printf '\n;\n')
check $? "Javascript files concatenated with a separator"
[ ! -e static/gen/bundle.js ] && [ ! -e static/generated.css ]
check $? "files generated by CONF_PKG_MINIFY removed"
minified 0.4.6 link.css && [ ! -L "$AWS_COPY/0.4.6/link.css" ]
check $? "file pointed by a symlink minified"
unchanged 0.4.6 icon.svg && unchanged 0.4.6 page.html && unchanged 0.4.6 notes.txt && unchanged 0.4.6 data.bin
check $? "other files unchanged"
unchanged 0.4.6 lib.min.js && unchanged 0.4.6 pre.js
check $? "already minified and already compressed files unchanged"
unchanged 0.4.6 bad.js && [[ "$MINIFY_OUTPUT" == *"Unable to minify file 'bad.js'"* ]]
check $? "warning and original file sent when the minification fails"
[ "$(git status --porcelain)" = "" ]
check $? "static files of the repository not modified"
# with compression
write_minify_conf " 1 " 1
EDITOR=true "$DPK" pkg --tag=0.4.7 > /dev/null 2>&1
check $? "the command succeeds with compression"
grep -F "s3://bucket/0.4.7/app.js " "$AWS_LOG" | grep -q -- "--content-encoding gzip" && [ "$(gunzip -c < "$AWS_COPY/0.4.7/app.js" | head -1)" = "MINIFIED" ]
check $? "file minified then compressed"
minified 0.4.7 style.css
check $? "small file minified but not compressed"
grep -q "^s3 cp pre\.js\.gz s3://bucket/0.4.7/pre.js " "$AWS_LOG" && cmp -s static/pre.js.gz "$AWS_COPY/0.4.7/pre.js"
check $? "already compressed file sent in place of the original one"
[ ! -e "$AWS_COPY/0.4.7/link.css" ]
check $? "symlink ignored by the file by file upload"
chmod 755 static/readonly
# error when the minified file is written
cat > "$TEST_DIR/bin/cat" << 'EOF'
#!/bin/bash
PATH="/usr/bin:/bin"
[ "$CAT_FAIL" = "1" ] && [ $# -eq 0 ] && head -c 4 && exit 1
exec cat "$@"
EOF
chmod +x "$TEST_DIR/bin/cat"
write_minify_conf 1 0
MINIFY_OUTPUT="$(CAT_FAIL=1 EDITOR=true "$DPK" pkg --tag=0.4.8 2>&1)"
check $? "the command succeeds when the minified files can't be written"
unchanged 0.4.8 app.js && unchanged 0.4.8 style.css && [[ "$MINIFY_OUTPUT" == *"Unable to minify file 'app.js'"* ]]
check $? "warning and original files sent (not truncated)"
rm -f "$TEST_DIR/bin/cat"
# version of the minification program which is too old for Javascript
write_minify_conf "js css html" 0
MINIFY_OUTPUT="$(MINIFY_VERSION=2.20.17 EDITOR=true "$DPK" pkg --tag=0.4.9 2>&1)"
check $? "the command succeeds with an old version of the minification program"
unchanged 0.4.9 app.js && unchanged 0.4.9 page.html && minified 0.4.9 style.css && minified 0.4.9 generated.css
check $? "Javascript and HTML files sent unminified, CSS files minified"
grep -q "one" "$AWS_COPY/0.4.9/gen/bundle.js" && grep -q "two" "$AWS_COPY/0.4.9/gen/bundle.js" && ! grep -q "MINIFIED" "$AWS_COPY/0.4.9/gen/bundle.js"
check $? "Javascript file generated by CONF_PKG_MINIFY only concatenated"
[[ "$MINIFY_OUTPUT" == *"unminified to Amazon S3: js html"* ]] && [[ "$MINIFY_OUTPUT" == *"file 'static/gen/bundle.js' is not minified"* ]]
check $? "warnings displayed"
# source of CONF_PKG_MINIFY in error
write_minify_conf 0 0
echo "BAD" > src/two.js
git commit -qam "syntax error"
git push -q origin main
MINIFY_OUTPUT="$(EDITOR=true "$DPK" pkg --tag=0.4.10 2>&1)"
check $? "the command succeeds when a file can't be minified"
grep -q "one" "$AWS_COPY/0.4.10/gen/bundle.js" && grep -q "BAD" "$AWS_COPY/0.4.10/gen/bundle.js" && ! grep -q "MINIFIED" "$AWS_COPY/0.4.10/gen/bundle.js" && [[ "$MINIFY_OUTPUT" == *"Unable to minify file 'static/gen/bundle.js'"* ]]
check $? "warning and file generated by CONF_PKG_MINIFY only concatenated"
# list of extensions
write_minify_conf "js
	html svg" 0
EDITOR=true "$DPK" pkg --tag=0.4.11 > /dev/null 2>&1
minified 0.4.11 app.js && minified 0.4.11 page.html && minified 0.4.11 icon.svg && unchanged 0.4.11 style.css
check $? "only listed extensions minified"
# deactivated
write_minify_conf 0 0
EDITOR=true "$DPK" pkg --tag=0.4.12 > /dev/null 2>&1
unchanged 0.4.12 app.js && grep -q "^s3 sync static s3://bucket/0.4.12 " "$AWS_LOG"
check $? "no minification when the option is set to 0"
# upload failure
write_minify_conf 1 0
AWS_FAIL=1 EDITOR=true "$DPK" pkg --tag=0.4.13 > /dev/null 2>&1
[ $? -eq 23 ]
check $? "S3 upload failure reported (exit code 23)"
# configuration error
for VALUE in "js,css" "true" "-n" "*"; do
	write_minify_conf "$VALUE" 0
	EDITOR=true "$DPK" pkg --tag=0.4.14 > /dev/null 2>&1
	[ $? -eq 20 ]
	check $? "refused with an unknown extension '$VALUE' (exit code 20)"
done
# copy of the static files in error (because of a dangling symlink)
write_minify_conf 1 0
ln -s nonexistent static/dangling.css
git add static
git commit -qm "dangling symlink"
git push -q origin main
MINIFY_OUTPUT="$(EDITOR=true "$DPK" pkg --tag=0.4.14 2>&1)"
check $? "the command succeeds when the static files can't be copied"
unchanged 0.4.14 app.js && [[ "$MINIFY_OUTPUT" == *"Unable to create a temporary copy of 'static'"* ]]
check $? "warning and files sent unminified"
git rm -q static/dangling.css
git commit -qm "remove dangling symlink"
git push -q origin main
# wrong minification program
write_minify_conf 1 0
printf '#!/bin/sh\necho "1.0.0"\n' > "$TEST_DIR/bin/minify"
MINIFY_OUTPUT="$(EDITOR=true "$DPK" pkg --tag=0.4.15 2>&1)"
check $? "the command succeeds without the minification program"
git rev-parse --verify --quiet "0.4.15" > /dev/null
check $? "the tag was created"
unchanged 0.4.15 app.js && [[ "$MINIFY_OUTPUT" == *"static files are sent unminified"* ]]
check $? "warning and files sent unminified"
grep -q "one" "$AWS_COPY/0.4.15/gen/bundle.js" && ! grep -q "MINIFIED" "$AWS_COPY/0.4.15/gen/bundle.js" && [[ "$MINIFY_OUTPUT" == *"files are concatenated but not minified"* ]]
check $? "warning and files generated by CONF_PKG_MINIFY only concatenated"
# missing source of CONF_PKG_MINIFY
write_minify_conf 0 0
git rm -q src/two.js
git commit -qm "missing source"
git push -q origin main
EDITOR=true "$DPK" pkg --tag=0.4.16 > /dev/null 2>&1
[ $? -eq 20 ]
check $? "refused when a source of CONF_PKG_MINIFY is missing (exit code 20)"
[ ! -e static/gen/bundle.js ] && [ "$(git status --porcelain)" = "" ]
check $? "no generated file left"
# cleanup (all the working directories of the minification program must have been removed)
[ -s "$MINIFY_LOG" ] && ! sort -u "$MINIFY_LOG" | xargs ls -d 2> /dev/null | grep -q .
check $? "temporary directories removed"

test_end

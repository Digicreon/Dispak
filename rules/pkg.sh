#!/bin/bash

# "pkg" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="pkg"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="tag"

# Show help for this rule.
rule_help_pkg() {
	echo "  dpk $(ansi bold)pkg$(ansi reset) $(ansi dim)[--tag=X.Y.Z]$(ansi reset)"
	echo "      $(ansi dim)Create a new tag. Upload files to AWS S3 (see $(ansi reset)s3$(ansi dim) rule) only if the tag is a stable version.$(ansi reset)"
}

# Execution of the rule
rule_exec_pkg() {
	check_git
	check_next_tag
	# check URL
	_pkg_check_url
	# check master branch
	if [ "$(git rev-parse --abbrev-ref HEAD)" != "master" ]; then
		abort "$(ansi red)You have to be on the $(ansi reset)master$(ansi red) branch.$(ansi reset)"
	fi
	# check uncommitted files
	if [ "$(git status -s)" != "" ]; then
		warn "$(ansi yellow)There is some uncommitted files.$(ansi reset)"
		git status -s
		read -p "Do you want to proceed anyway? [y/N] " ANSWER
		if [ "$ANSWER" != "y" ] && [ "$ANSWER" != "Y" ]; then
			exit 11
		fi
	fi
	# execute pre-packaging scripts
	_pkg_pre_scripts
	# commit database migration file
	if [ -f "$GIT_REPO_PATH/etc/database/migrations/current" ] && [ "$(du "$GIT_REPO_PATH/etc/database/migrations/current" | cut -f1)" != "0" ]; then
		if [ "$(git status -s | grep "^A" | wc -l)" != "0" ]; then
			abort "$(ansi red)Need to commit database migration files, but you have files waiting to be committed.$(ansi reset)"
		fi
		git mv "$GIT_REPO_PATH/etc/database/migrations/current" "$GIT_REPO_PATH/etc/database/migrations/${DPK_OPTIONS["tag"]}"
		touch "$GIT_REPO_PATH/etc/database/migrations/current"
		git add "$GIT_REPO_PATH/etc/database/migrations/${DPK_OPTIONS["tag"]}" "$GIT_REPO_PATH/etc/database/migrations/current"
		git commit -m "Added database migration file for version ${DPK_OPTIONS["tag"]}"
		git push origin master
	fi
	# minify files
	_pkg_minify
	# create tag
	echo "$(ansi bold)Creating local tag '${DPK_OPTIONS["tag"]}'...$(ansi reset)"
	git tag -a "${DPK_OPTIONS["tag"]}"
	echo "$(ansi bold)Pushing tag to server...$(ansi reset)"
	git push origin "${DPK_OPTIONS["tag"]}"
	# send static files to Amazon S3
	_pkg_s3
	# unminify (remove minified files that are not version controlled)
	_pkg_unminify
	# execute post-packaging scripts
	_pkg_post_scripts
}

# _pkg_pre_scripts()
# Execute pre-packaging scripts.
_pkg_pre_scripts() {
	if [ "$CONF_PKG_SCRIPTS_PRE" = "" ]; then
		return
	fi
	echo "$(ansi bold)Execute pre-packaging scripts$(ansi reset)"
	for _SCRIPT in $CONF_PKG_SCRIPTS_PRE; do
		echo "> $(ansi dim)$_SCRIPT$(ansi reset)"
		if [ ! -x "$_SCRIPT" ]; then
			chmod +x "$_SCRIPT"
		fi
		$_SCRIPT
		if [ $? -ne 0 ]; then
			abort "$(ansi red)Execution failed.$(ansi reset)"
		fi
	done
	echo "$(ansi gree)Done$(ansi reset)"
}

# _pkg_post_scripts()
# Execute post-packaging scripts.
_pkg_post_scripts() {
	if [ "$CONF_PKG_SCRIPTS_POST" = "" ]; then
		return
	fi
	echo "$(ansi bold)Execute post-packaging scripts$(ansi reset)"
	for _SCRIPT in $CONF_PKG_SCRIPTS_POST; do
		echo "> $(ansi dim)$_SCRIPT$(ansi reset)"
		if [ ! -x "$_SCRIPT" ]; then
			chmod +x "$_SCRIPT"
		fi
		$_SCRIPT
		if [ $? -ne 0 ]; then
			abort "$(ansi red)Execution failed.$(ansi reset)"
		fi
	done
	echo "$(ansi gree)Done$(ansi reset)"
}

# _pkg_unminify()
# Delete minified files that are not version controlled.
_pkg_unminify() {
	if [ ${#CONF_PKG_MINIFY[@]} -eq 0 ]; then
		# no file to unminify
		return
	fi
	for _FILE in ${!CONF_PKG_MINIFY[@]}; do
		if ! git ls-files --error-unmatch "$_FILE" 2> /dev/null ; then
			rm -f "$_FILE"
		fi
	done
}

# _pkg_minify()
# Minify files. If the generated files are already version controlled, they are committed.
_pkg_minify() {
	if [ ${#CONF_PKG_MINIFY[@]} -eq 0 ]; then
		# no file to minify
		return
	fi
	if ! which minify > /dev/null; then
		# minifier program not found
		abort "Minification program '$(ansi dim)minify$(ansi reset)' not found.
  Please install NodeJS with NPM, and the 'minifier' package. See https://www.npmjs.com/package/minifier
  "
	fi
	# checks modified files
	for _FILE in ${!CONF_PKG_MINIFY[@]}; do
		if [ -e "$_FILE" ] && git ls-files --error-unmatch "$_FILE" 2> /dev/null && [ "$(git diff --name-only "$_FILE")" != "" ]; then
			abort "Need to generate the file '$(ansi dim)$_FILE$(ansi reset)' from its source but is is locally modified.i
  $(ansi yellow)Please, commit/stash/rollback the file.$(ansi reset)
"
		fi
	done
	# minification
	echo "$(ansi bold)Files minification$(ansi reset)"
	for _FILE in ${!CONF_PKG_MINIFY[@]}; do
		echo "$(ansi dim)> $_FILE$(ansi reset)"
		minify --output "$_FILE" "${CONF_PKG_MINIFY["$_FILE"]}" > /dev/null
		if [ $? -ne 0 ]; then
			abort "Unable to minify file '$(ansi dim)$_FILE$(ansi reset)'."
		fi
	done
	# commit minified files that were alreay version controlled
	NEED_COMMIT=0
	for _FILE in ${!CONF_PKG_MINIFY[@]}; do
		if git ls-files --error-unmatch "$_FILE" 2> /dev/null && [ "$(git diff --name-only "$_FILE")" != "" ]; then
			git add "$_FILE"
			NEED_COMMIT=1
		fi
	done
	if [ $NEED_COMMIT -ne 0 ]; then
		git commit -m "Added minified files for version ${DPK_OPTIONS["tag"]}."
		git push origin master
	fi
}

# _pkg_s3()
# Send static files to Amazon S3
_pkg_s3() {
	if [ "${DPK_OPTIONS["tag"]}" = "" ] || [ "${DPK_OPTIONS["tag"]}" = "master" ]; then
		return
	fi
	TAG_MINOR=$(echo "${DPK_OPTIONS["tag"]}" | cut -d"." -f2)
	if [ "$(($TAG_MINOR % 2))" != "0" ]; then
		# not a stable tag
		return
	fi
	if [ ${#CONF_PKG_S3[@]} -eq 0 ]; then
		# nothing to copy to S3
		return
	fi
	# check aws program
	check_aws
	# copy to S3
	echo "$(ansi bold)Copy files to Amazon S3$(ansi reset)"
	for _S3 in ${!CONF_PKG_S3[@]}; do
		FOUND_MASTER_LINK=0
		if [ -L "${CONF_PKG_S3["$_S3"]}/master" ] && [ "$(readlink -f "${CONF_PKG_S3["$_S3"]}/master")" = "${CONF_PKG_S3["$_S3"]}" ]; then
			rm -f "${CONF_PKG_S3["$_S3"]}/master"
			FOUND_MASTER_LINK=1
		fi
		echo "$(ansi dim)> $_S3$(ansi reset)"
		aws s3 sync "${CONF_PKG_S3["$_S3"]}" "s3://${_S3}/${DPK_OPTIONS["tag"]}" --acl public-read
		if [ $FOUND_MASTER_LINK -eq 1 ]; then
			ln -s "${CONF_PKG_S3["$_S3"]}" "${CONF_PKG_S3["$_S3"]}/master"
		fi
	done
}

# _pkg_check_url()
# Check if a configured URL responds correctly.
_pkg_check_url() {
	if [ "$CONF_PKG_CHECK_URL" != "" ]; then
		if [ "$(curl -I -k "$CONF_PKG_CHECK_URL" 2> /dev/null | head -1 | cut -d' ' -f 2)" != "200" ]; then
			abort "$(ansi red)The URL $(ansi reset)$(ansi dim)$CONF_PKG_CHECK_URL$(ansi reset) $(ansi red)is returning an error.$(ansi reset)"
		fi
	fi
}


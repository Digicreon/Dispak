#!/usr/bin/env bash

# "pkg" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="pkg"

# Rule's section (for documentation).
RULE_SECTION="Tag management"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="tag"

# Definition of configuration associative arrays.
declare -A CONF_PKG_MINIFY
declare -A CONF_PKG_S3

# Show help for this rule.
rule_help_pkg() {
	echo "   dpk $(ansi bold)pkg$(ansi reset) $(ansi dim)[$(ansi reset)--tag$(ansi dim)=X.Y.Z]$(ansi reset)"
	echo "       $(ansi dim)Create a new tag. Upload files to AWS S3 (see configuration file) only if the tag is a stable version.$(ansi reset)"
	echo "       --tag $(ansi dim)Use the given tag, don't ask it interactively.$(ansi reset)"
}

# Execution of the rule
rule_exec_pkg() {
	check_git
	check_platform
	# check if there was some commits since the last tag
	if [ "$(git tag)" != "" ] && [ "$(git describe --long | cut -d"-" -f 2)" -eq 0 ]; then
		abort "No file committed since last tag."
	fi
	# get next tags number
	check_next_tag
	# check URL
	_pkg_check_url
	# check 'main' branch
	check_git_main
	# check the repo is clean
	check_git_clean
	# check unpushed files
	check_git_pushed
	# execute pre-packaging scripts
	_pkg_pre_scripts
	# commit database migration file
	if [ -f "$GIT_REPO_PATH/etc/database/migrations/current" ] && [ "$(du "$GIT_REPO_PATH/etc/database/migrations/current" | cut -f1)" != "0" ]; then
		if [ "$(git status --short | grep --count "^A")" != "0" ]; then
			abort "$(ansi red)Need to commit database migration files, but you have files waiting to be committed.$(ansi reset)"
		fi
		git mv "$GIT_REPO_PATH/etc/database/migrations/current" "$GIT_REPO_PATH/etc/database/migrations/${DPK_OPT["tag"]}"
		touch "$GIT_REPO_PATH/etc/database/migrations/current"
		git add "$GIT_REPO_PATH/etc/database/migrations/${DPK_OPT["tag"]}" "$GIT_REPO_PATH/etc/database/migrations/current"
		git commit -m "Added database migration file for version ${DPK_OPT["tag"]}"
		git push origin "$CONF_GIT_MAIN"
	fi
	# minify files
	_pkg_minify
	# create log file
	echo "$(ansi bold)Creating default log message...$(ansi reset)"
	TAGLOGFILE="$(mktemp --tmpdir=/tmp dispak-log.XXXXXXXXXX)"
	git log "$(git tag | sort -V | tail -1)"..HEAD --pretty=format:%s > $TAGLOGFILE
	echo >> $TAGLOGFILE
	echo "#" >> $TAGLOGFILE
	echo "# Write log message for tag: ${DPK_OPT["tag"]}" >> $TAGLOGFILE
	echo "#     Lines starting with '#' will be ignored." >> $TAGLOGFILE
	EDITOR_PROGRAM="vim"
	if [ "${EDITOR}" != "" ]; then
		EDITOR_PROGRAM="${EDITOR}"
	elif [ "${VISUAL}" != "" ]; then
		EDITOR_PROGRAM="${VISUAL}"
	fi
	$EDITOR_PROGRAM $TAGLOGFILE
	grep -ve "^#" $TAGLOGFILE > $TAGLOGFILE.final
	# create tag
	echo "$(ansi bold)Creating local tag '${DPK_OPT["tag"]}'...$(ansi reset)"
	git tag -a "${DPK_OPT["tag"]}" --file=$TAGLOGFILE.final
	# delete log file
	rm -f $TAGLOGFILE $TAGLOGFILE.final
	# push tag to server
	echo "$(ansi bold)Pushing tag to server...$(ansi reset)"
	git push origin "${DPK_OPT["tag"]}"
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
		_SCRIPT="$(echo $_SCRIPT | sed 's/#/ /')"
		_EXEC="$(echo "$_SCRIPT" | cut -d" " -f 1)"
		echo "> $(ansi dim)$_SCRIPT$(ansi reset)"
		if [ ! -x "$_EXEC" ]; then
			chmod +x "$_EXEC"
		fi
		$_SCRIPT "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}"
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
		_SCRIPT="$(echo $_SCRIPT | sed 's/#/ /')"
		_EXEC="$(echo "$_SCRIPT" | cut -d" " -f 1)"
		echo "> $(ansi dim)$_SCRIPT$(ansi reset)"
		if [ ! -x "$_EXEC" ]; then
			chmod +x "$_EXEC"
		fi
		$_SCRIPT "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}"
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
	# loop on minified files
	for _FILE in "${!CONF_PKG_MINIFY[@]}"; do
		# check if the minified file was already committed
		if git ls-files --error-unmatch "$_FILE" 2> /dev/null; then
			# the file is under Git, revert the changes
			git restore "$_FILE"
		else
			# the file is not managed with Git, delete it
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
			abort "Need to generate the file '$(ansi dim)$_FILE$(ansi reset)' from its source but it is locally modified.
  $(ansi yellow)Please, commit/stash/rollback the file.$(ansi reset)
"
		fi
	done
	# minification
	echo "$(ansi bold)Files minification$(ansi reset)"
	for _FILE in ${!CONF_PKG_MINIFY[@]}; do
		echo "$(ansi dim)> $_FILE$(ansi reset)"
		minify -o "$_FILE" ${CONF_PKG_MINIFY["$_FILE"]} > /dev/null
		if [ $? -ne 0 ]; then
			abort "Unable to minify file '$(ansi dim)$_FILE$(ansi reset)'."
		fi
	done
	# commit minified files that were alreay version controlled (only if the source and minified files are not the same)
	#if [ "$_FILE" != "${CONF_PKG_MINIFY["$_FILE"]}" ]; then
	#	NEED_COMMIT=0
	#	for _FILE in "${!CONF_PKG_MINIFY[@]}"; do
	#		if git ls-files --error-unmatch "$_FILE" 2> /dev/null && [ "$(git diff --name-only "$_FILE")" != "" ]; then
	#			git add "$_FILE"
	#			NEED_COMMIT=1
	#		fi
	#	done
	#	if [ $NEED_COMMIT -ne 0 ]; then
	#		git commit -m "Added minified files for version ${DPK_OPT["tag"]}."
	#		git push origin "$CONF_GIT_MAIN"
	#	fi
	#fi
}

# _pkg_s3()
# Send static files to Amazon S3
_pkg_s3() {
	if [ "${DPK_OPT["tag"]}" = "" ] || [ "${DPK_OPT["tag"]}" = "$CONF_GIT_MAIN" ]; then
		return
	fi
	TAG_MINOR=$(echo "${DPK_OPT["tag"]}" | cut -d"." -f2)
	if [ "$(($TAG_MINOR % 2))" != "0" ] && [ "$CONF_PKG_S3_UNSTABLE" != "1" ]; then
		# not a stable tag
		return
	fi
	if [ ${#CONF_PKG_S3[@]} -eq 0 ]; then
		# nothing to copy to S3
		return
	fi
	# check aws program
	check_aws
	# loop on paths that must be copied to S3
	echo "$(ansi bold)Copy files to Amazon S3$(ansi reset)"
	for _S3 in ${!CONF_PKG_S3[@]}; do
		# check if the source path exists
		if [ ! -d "${CONF_PKG_S3["$_S3"]}" ]; then
			abort "The path '${CONF_PKG_S3["$_S3"]}' doesn't exist."
		fi
		# search for a "main" symlink (and remove it)
		FOUND_MAIN_LINK=0
		if [ -L "${CONF_PKG_S3["$_S3"]}/$CONF_GIT_MAIN" ] && [ "$(readlink -f "${CONF_PKG_S3["$_S3"]}/$CONF_GIT_MAIN")" = "${CONF_PKG_S3["$_S3"]}" ]; then
			rm -f "${CONF_PKG_S3["$_S3"]}/$CONF_GIT_MAIN"
			FOUND_MAIN_LINK=1
		fi
		# copy files to Amazon S3
		echo "$(ansi dim)> $_S3$(ansi reset)"
		# check if the static files (in this path) must be compressed
		if [ "$CONF_PKG_S3_COMPRESS" != "1" ]; then
			# no compression, copy files in bulk
			aws s3 sync "${CONF_PKG_S3["$_S3"]}" "s3://${_S3}/${DPK_OPT["tag"]}" --acl public-read --cache-control "max-age=31536000"
		else
			# process files one by one, to compress text files before sending to Amazon S3
			# move to the source path
			pushd "${CONF_PKG_S3["$_S3"]}" > /dev/null
			# loop on the files to compress them (only text files) and send them to Amazon S3
			while read -r _FILE; do
				MUST_COMPRESS=1
				# remove "./" at the beginning of the file name
				_FILE="${_FILE#./}"
				# don't compress this file if it's not a text file
				_MIME="$(file --mime-type -b "$_FILE")"
				_SHORTMIME="${_MIME:0:4}"
				if [ "$_SHORTMIME" != "text" ] && [ "$_MIME" != "application/json" ] && [ "$_MIME" != "image/svg+xml" ]; then
					MUST_COMPRESS=0
				fi
				# don't compress this file if another file exist with the same name + ".gz" suffix
				if [ -e "$_FILE.gz" ]; then
					MUST_COMPRESS=0
				fi
				# don't compress this file if it's under Git and has been modified (and is not a minified file)
				if [ "$(git status --porcelain "$_FILE" 2> /dev/null)" != "" ] && [ -v CONF_PKG_MINIFY["$_FILE"] ]; then
					MUST_COMPRESS=0
				fi
				# compress the file if needed
				_SRC="$_FILE"
				if [ $MUST_COMPRESS -eq 1 ]; then
					gzip -c -f -9 "$_FILE" > "${_FILE}.gz"
					if [ $? -eq 0 ]; then
						_SRC="${_FILE}.gz"
					else
						MUST_COMPRESS=0
					fi
				fi
				# send the file to Amazon S3
				if [ $MUST_COMPRESS -eq 1 ]; then
					# gzipped file
					aws s3 cp "$_SRC" "s3://${_S3}/${DPK_OPT["tag"]}/${_FILE}" --acl public-read --content-encoding gzip  --cache-control "max-age=31536000"
					# delete the gzipped file
					rm -f "${_FILE}.gz"
				else
					# raw file
					aws s3 cp "$_SRC" "s3://${_S3}/${DPK_OPT["tag"]}/${_FILE}" --acl public-read --cache-control "max-age=31536000"
				fi
			done <<< $(find . -type f)
			# get back to the previous directory
			popd > /dev/null
		fi
		# re-create the "main" symlink if it was found before
		if [ $FOUND_MAIN_LINK -eq 1 ]; then
			ln -s "${CONF_PKG_S3["$_S3"]}" "${CONF_PKG_S3["$_S3"]}/$CONF_GIT_MAIN"
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


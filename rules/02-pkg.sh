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
RULE_OPTIONAL_PARAMS="tag s3-force"

# Definition of configuration associative arrays.
declare -A CONF_PKG_CONCAT
declare -A CONF_PKG_MINIFY
declare -A CONF_PKG_S3

# Path to the file which contains the version number of the last upload to Amazon S3 (relative to the repository root).
_PKG_S3_VERSION_FILE="etc/s3_upload_last_tag"

# Minimum size (in bytes) of the files which are compressed before being sent to Amazon S3.
_PKG_S3_COMPRESS_MIN_SIZE=1024

# Tell if the static files must be sent to Amazon S3 (set by the _pkg_s3_prepare() function).
# @type	bool
_PKG_S3_SEND=0

# Show help for this rule.
rule_help_pkg() {
	echo "   dpk $(ansi bold)pkg$(ansi reset) $(ansi dim)[$(ansi reset)--tag$(ansi dim)=X.Y.Z]$(ansi reset)"
	echo "       $(ansi dim)Create a new tag. Upload files to AWS S3 (see configuration file) only if the tag is a stable version.$(ansi reset)"
	echo "       --tag $(ansi dim)Use the given tag, don't ask it interactively.$(ansi reset)"
	echo "       --s3-force $(ansi dim)Upload files to AWS S3 even if they were not modified (when CONF_PKG_S3_BEHAVIOUR is 'modified').$(ansi reset)"
}

# Execution of the rule
rule_exec_pkg() {
	local TAGLOGFILE EDITOR_PROGRAM
	check_git
	check_platform
	# check if there was some commits since the last tag
	if [ "$(git tag)" != "" ] && [ "$(git describe --long | cut -d"-" -f 2)" -eq 0 ]; then
		abort "No file committed since last tag." $DPK_EXIT_GIT
	fi
	# get next tags number
	check_next_tag
	# check URL
	_pkg_check_url
	# check Amazon S3 configuration
	_pkg_s3_check_conf
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
			abort "$(ansi red)Need to commit database migration files, but you have files waiting to be committed.$(ansi reset)" $DPK_EXIT_GIT_DIRTY
		fi
		git mv "$GIT_REPO_PATH/etc/database/migrations/current" "$GIT_REPO_PATH/etc/database/migrations/${DPK_OPT["tag"]}"
		touch "$GIT_REPO_PATH/etc/database/migrations/current"
		git add "$GIT_REPO_PATH/etc/database/migrations/${DPK_OPT["tag"]}" "$GIT_REPO_PATH/etc/database/migrations/current"
		git commit -m "Added database migration file for version ${DPK_OPT["tag"]}"
		git push origin "$CONF_GIT_MAIN"
	fi
	# check if static files must be sent to Amazon S3 (and commit the S3 version file)
	_pkg_s3_prepare
	# check the minification program availability (before any file generation)
	_pkg_check_minify
	# remove generated files if the packaging process is interrupted
	trap 'cd "$GIT_REPO_PATH" 2> /dev/null; _pkg_unminify; _pkg_unconcat' EXIT
	# concat files
	_pkg_concat
	# minify files
	_pkg_minify
	# create log file
	dpk_echo "$(ansi bold)Creating default log message...$(ansi reset)"
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
	dpk_echo "$(ansi bold)Creating local tag '${DPK_OPT["tag"]}'...$(ansi reset)"
	git tag -a "${DPK_OPT["tag"]}" --file=$TAGLOGFILE.final
	# delete log file
	rm -f $TAGLOGFILE $TAGLOGFILE.final
	# push tag to server
	dpk_echo "$(ansi bold)Pushing tag to server...$(ansi reset)"
	git push origin "${DPK_OPT["tag"]}"
	# send static files to Amazon S3
	_pkg_s3
	# execute post-S3 upload scripts
	_pkg_s3_scripts
	# unminify (remove minified files that are not version controlled)
	_pkg_unminify
	# unconcat (remove concatenated files that are not version controlled)
	_pkg_unconcat
	# remove the cleanup handler
	trap - EXIT
	# execute post-packaging scripts
	_pkg_post_scripts
}

# _pkg_pre_scripts()
# Execute pre-packaging scripts.
_pkg_pre_scripts() {
	local _SCRIPT _EXEC
	if [ "$CONF_PKG_SCRIPTS_PRE" = "" ]; then
		return
	fi
	dpk_echo "$(ansi bold)Execute pre-packaging scripts$(ansi reset)"
	for _SCRIPT in $CONF_PKG_SCRIPTS_PRE; do
		_SCRIPT="$(echo $_SCRIPT | sed 's/#/ /')"
		_EXEC="$(echo "$_SCRIPT" | cut -d" " -f 1)"
		dpk_echo "> $(ansi dim)$_SCRIPT$(ansi reset)"
		if [ ! -x "$_EXEC" ]; then
			chmod +x "$_EXEC"
		fi
		$_SCRIPT "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}"
		if [ $? -ne 0 ]; then
			abort "$(ansi red)Execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_PKG_PRE
		fi
	done
	dpk_echo "$(ansi green)Done$(ansi reset)"
}

# _pkg_post_scripts()
# Execute post-packaging scripts.
_pkg_post_scripts() {
	local _SCRIPT _EXEC
	if [ "$CONF_PKG_SCRIPTS_POST" = "" ]; then
		return
	fi
	dpk_echo "$(ansi bold)Execute post-packaging scripts$(ansi reset)"
	for _SCRIPT in $CONF_PKG_SCRIPTS_POST; do
		_SCRIPT="$(echo $_SCRIPT | sed 's/#/ /')"
		_EXEC="$(echo "$_SCRIPT" | cut -d" " -f 1)"
		dpk_echo "> $(ansi dim)$_SCRIPT$(ansi reset)"
		if [ ! -x "$_EXEC" ]; then
			chmod +x "$_EXEC"
		fi
		$_SCRIPT "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}"
		if [ $? -ne 0 ]; then
			abort "$(ansi red)Execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_PKG_POST
		fi
	done
	dpk_echo "$(ansi green)Done$(ansi reset)"
}

# _pkg_s3_scripts()
# Execute post-S3 upload scripts (only if static files were sent to Amazon S3).
_pkg_s3_scripts() {
	local _SCRIPT _EXEC
	if [ "$_PKG_S3_SEND" != "1" ] || [ "$CONF_PKG_SCRIPTS_S3" = "" ]; then
		return
	fi
	dpk_echo "$(ansi bold)Execute post-S3 upload scripts$(ansi reset)"
	for _SCRIPT in $CONF_PKG_SCRIPTS_S3; do
		_SCRIPT="$(echo $_SCRIPT | sed 's/#/ /')"
		_EXEC="$(echo "$_SCRIPT" | cut -d" " -f 1)"
		dpk_echo "> $(ansi dim)$_SCRIPT$(ansi reset)"
		if [ ! -x "$_EXEC" ]; then
			chmod +x "$_EXEC"
		fi
		$_SCRIPT "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}"
		if [ $? -ne 0 ]; then
			abort "$(ansi red)Execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_PKG_S3
		fi
	done
	dpk_echo "$(ansi green)Done$(ansi reset)"
}

# _pkg_unconcat()
# Delete concatenated files that are not version controlled.
_pkg_unconcat() {
	local _FILE
	if [ ${#CONF_PKG_CONCAT[@]} -eq 0 ]; then
		# no file to unconcat
		return
	fi
	# loop on concatenated files
	for _FILE in "${!CONF_PKG_CONCAT[@]}"; do
		# check if the concatenated file was already committed
		if git ls-files --error-unmatch "$_FILE" > /dev/null 2>&1; then
			# the file is under Git, revert the changes
			git restore "$_FILE"
		else
			# the file is not managed with Git, delete it
			rm -f "$_FILE"
		fi
	done
}

# _pkg_concat()
# Concatenate files.
_pkg_concat() {
	local _FILE
	if [ ${#CONF_PKG_CONCAT[@]} -eq 0 ]; then
		# no file to concatenate
		return
	fi
	# checks modified files
	for _FILE in ${!CONF_PKG_CONCAT[@]}; do
		if [ -e "$_FILE" ] && git ls-files --error-unmatch "$_FILE" > /dev/null 2>&1 && [ "$(git diff --name-only "$_FILE")" != "" ]; then
			abort "Need to generate the file '$(ansi dim)$_FILE$(ansi reset)' from its source but it is locally modified.
  $(ansi yellow)Please, commit/stash/rollback the file.$(ansi reset)
" $DPK_EXIT_GIT_DIRTY
		fi
	done
	# concatenation
	dpk_echo "$(ansi bold)Files concatenation$(ansi reset)"
	for _FILE in ${!CONF_PKG_CONCAT[@]}; do
		# don't process entries with an empty list of source files
		if [ -z "${CONF_PKG_CONCAT["$_FILE"]//[[:space:]]/}" ]; then
			warn "Empty list of files to concatenate for the file '$(ansi dim)$_FILE$(ansi reset)'."
			continue
		fi
		dpk_echo "$(ansi dim)> $_FILE$(ansi reset)"
		cat ${CONF_PKG_CONCAT["$_FILE"]} > "$_FILE"
		if [ $? -ne 0 ]; then
			abort "Unable to concatenate file '$(ansi dim)$_FILE$(ansi reset)'." $DPK_EXIT_ENV
		fi
	done
}

# _pkg_unminify()
# Delete minified files that are not version controlled.
_pkg_unminify() {
	local _FILE
	if [ ${#CONF_PKG_MINIFY[@]} -eq 0 ]; then
		# no file to unminify
		return
	fi
	# loop on minified files
	for _FILE in "${!CONF_PKG_MINIFY[@]}"; do
		# check if the minified file was already committed
		if git ls-files --error-unmatch "$_FILE" > /dev/null 2>&1; then
			# the file is under Git, revert the changes
			git restore "$_FILE"
		else
			# the file is not managed with Git, delete it
			rm -f "$_FILE"
		fi
	done
}

# _pkg_check_minify()
# Check that the minification program is installed.
_pkg_check_minify() {
	if [ ${#CONF_PKG_MINIFY[@]} -eq 0 ]; then
		# no file to minify
		return
	fi
	if ! which minify > /dev/null; then
		# minifier program not found
		abort "Minification program '$(ansi dim)minify$(ansi reset)' not found.
  Please install it (on Ubuntu: $(ansi dim)apt install minify$(ansi reset)). See https://github.com/tdewolff/minify
  " $DPK_EXIT_ENV_PROGRAM
	fi
	if ! minify --version < /dev/null 2> /dev/null | grep -q "^minify v"; then
		# another 'minify' program (like the obsolete NPM 'minifier' package)
		abort "The '$(ansi dim)minify$(ansi reset)' program found in the path ($(which minify)) is not tdewolff/minify.
  Please install it (on Ubuntu: $(ansi dim)apt install minify$(ansi reset)). See https://github.com/tdewolff/minify
  " $DPK_EXIT_ENV_PROGRAM
	fi
}

# _pkg_minify()
# Minify files. If the generated files are already version controlled, they are committed.
_pkg_minify() {
	local _FILE
	if [ ${#CONF_PKG_MINIFY[@]} -eq 0 ]; then
		# no file to minify
		return
	fi
	# checks modified files
	for _FILE in ${!CONF_PKG_MINIFY[@]}; do
		if [ -e "$_FILE" ] && git ls-files --error-unmatch "$_FILE" > /dev/null 2>&1 && [ "$(git diff --name-only "$_FILE")" != "" ]; then
			abort "Need to generate the file '$(ansi dim)$_FILE$(ansi reset)' from its source but it is locally modified.
  $(ansi yellow)Please, commit/stash/rollback the file.$(ansi reset)
" $DPK_EXIT_GIT_DIRTY
		fi
	done
	# minification
	dpk_echo "$(ansi bold)Files minification$(ansi reset)"
	for _FILE in ${!CONF_PKG_MINIFY[@]}; do
		dpk_echo "$(ansi dim)> $_FILE$(ansi reset)"
		minify -b -o "$_FILE" ${CONF_PKG_MINIFY["$_FILE"]} > /dev/null
		if [ $? -ne 0 ]; then
			abort "Unable to minify file '$(ansi dim)$_FILE$(ansi reset)'." $DPK_EXIT_ENV
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

# _pkg_s3_check_conf()
# Check the Amazon S3 configuration (abort if the upload behaviour is unknown).
_pkg_s3_check_conf() {
	if [ "$CONF_PKG_S3_BEHAVIOUR" != "" ] && [ "$CONF_PKG_S3_BEHAVIOUR" != "always" ] && [ "$CONF_PKG_S3_BEHAVIOUR" != "modified" ]; then
		abort "$(ansi red)Unknown value $(ansi reset)'$CONF_PKG_S3_BEHAVIOUR'$(ansi red) for the $(ansi reset)CONF_PKG_S3_BEHAVIOUR$(ansi red) configuration variable (must be 'always' or 'modified').$(ansi reset)" $DPK_EXIT_ENV
	fi
}

# _pkg_s3_prepare()
# Check if static files must be sent to Amazon S3 (set the _PKG_S3_SEND variable).
# If so, write the new tag number in the S3 version file, then commit and push it.
_pkg_s3_prepare() {
	local TAG_MINOR LAST_S3_TAG _FILE _SRC DIFF_STATUS
	local -a PATHS
	_PKG_S3_SEND=0
	if [ ${#CONF_PKG_S3[@]} -eq 0 ]; then
		# nothing to copy to S3
		return
	fi
	if [ "${DPK_OPT["tag"]}" = "" ] || [ "${DPK_OPT["tag"]}" = "$CONF_GIT_MAIN" ]; then
		return
	fi
	TAG_MINOR=$(echo "${DPK_OPT["tag"]}" | cut -d"." -f2)
	if [ "$(($TAG_MINOR % 2))" != "0" ] && [ "$CONF_PKG_S3_UNSTABLE" != "1" ]; then
		# not a stable tag
		return
	fi
	# check if static files were modified since the last upload
	if [ "$CONF_PKG_S3_BEHAVIOUR" = "modified" ] && [ ! -v DPK_OPT["s3-force"] ]; then
		LAST_S3_TAG=""
		if [ -f "$_PKG_S3_VERSION_FILE" ]; then
			LAST_S3_TAG="$(trim "$(head -1 "$_PKG_S3_VERSION_FILE")")"
		fi
		if [ "$LAST_S3_TAG" != "" ] && git rev-parse --verify --quiet "refs/tags/$LAST_S3_TAG" > /dev/null; then
			# list of watched paths: static files directories, and source files of concatenated and minified files
			PATHS=("${CONF_PKG_S3[@]}")
			for _FILE in "${!CONF_PKG_CONCAT[@]}"; do
				for _SRC in ${CONF_PKG_CONCAT["$_FILE"]}; do
					PATHS+=("$_SRC")
				done
			done
			for _FILE in "${!CONF_PKG_MINIFY[@]}"; do
				for _SRC in ${CONF_PKG_MINIFY["$_FILE"]}; do
					PATHS+=("$_SRC")
				done
			done
			git diff --quiet "$LAST_S3_TAG" HEAD -- "${PATHS[@]}" ":(exclude)$_PKG_S3_VERSION_FILE" 2> /dev/null
			DIFF_STATUS=$?
			if [ $DIFF_STATUS -eq 0 ]; then
				dpk_echo "$(ansi dim)No modification of static files since tag '$LAST_S3_TAG', no upload to Amazon S3.$(ansi reset)"
				return
			elif [ $DIFF_STATUS -ne 1 ]; then
				warn "$(ansi yellow)Unable to check modifications of static files since tag '$LAST_S3_TAG', they will be sent to Amazon S3.$(ansi reset)"
			fi
		fi
	fi
	_PKG_S3_SEND=1
	# check aws program
	check_aws
	# write the new tag number in the S3 version file, and commit it
	dpk_echo "$(ansi bold)Commit Amazon S3 version file$(ansi reset)"
	mkdir -p "$(dirname "$_PKG_S3_VERSION_FILE")"
	echo "${DPK_OPT["tag"]}" > "$_PKG_S3_VERSION_FILE"
	git add "$_PKG_S3_VERSION_FILE" && git commit -q -m "Amazon S3 upload of static files for version ${DPK_OPT["tag"]}" -- "$_PKG_S3_VERSION_FILE" && git push -q origin "$CONF_GIT_MAIN"
	if [ $? -ne 0 ]; then
		abort "$(ansi red)Unable to commit and push the file $(ansi reset)$_PKG_S3_VERSION_FILE$(ansi red).$(ansi reset)" $DPK_EXIT_GIT
	fi
}

# _pkg_s3_fail()
# Abort after an Amazon S3 upload error. Must be called from the _pkg_s3() function
# (re-create the "main" symlink if it was removed).
_pkg_s3_fail() {
	# get back to the repository root (the current directory may be the static files directory)
	cd "$GIT_REPO_PATH"
	if [ "$FOUND_MAIN_LINK" = "1" ]; then
		ln -s "${CONF_PKG_S3["$_S3"]}" "${CONF_PKG_S3["$_S3"]}/$CONF_GIT_MAIN"
	fi
	abort "$(ansi red)Upload to Amazon S3 failed.$(ansi reset)
  The tag '${DPK_OPT["tag"]}' was created, and the file '$_PKG_S3_VERSION_FILE' points to it, but its static files are not (or partially) uploaded.
  $(ansi yellow)Fix the problem, then create a new tag with the $(ansi reset)--s3-force$(ansi yellow) option to send the files again.$(ansi reset)
" $DPK_EXIT_ENV_S3
}

# _pkg_s3_is_text()
# Tell if a file is a text file (which can be compressed before being sent to Amazon S3).
# @param	string	Path to the file.
# @return	int	0 if it's a text file, 1 otherwise.
_pkg_s3_is_text() {
	case "$(file --mime-type -b "$1")" in
		text/* | \
		application/javascript | application/x-javascript | \
		application/json | application/manifest+json | \
		application/xml | application/xhtml+xml | application/rss+xml | application/atom+xml | \
		image/svg+xml)
			return 0
			;;
	esac
	return 1
}

# _pkg_s3()
# Send static files to Amazon S3
_pkg_s3() {
	local _S3 FOUND_MAIN_LINK _FILE MUST_COMPRESS _SRC _STATUS
	if [ "$_PKG_S3_SEND" != "1" ]; then
		return
	fi
	# loop on paths that must be copied to S3
	dpk_echo "$(ansi bold)Copy files to Amazon S3$(ansi reset)"
	for _S3 in ${!CONF_PKG_S3[@]}; do
		# check if the source path exists
		if [ ! -d "${CONF_PKG_S3["$_S3"]}" ]; then
			abort "The path '${CONF_PKG_S3["$_S3"]}' doesn't exist." $DPK_EXIT_ENV
		fi
		# search for a "main" symlink (and remove it)
		FOUND_MAIN_LINK=0
		if [ -L "${CONF_PKG_S3["$_S3"]}/$CONF_GIT_MAIN" ] && [ "$(readlink -f "${CONF_PKG_S3["$_S3"]}/$CONF_GIT_MAIN")" = "${CONF_PKG_S3["$_S3"]}" ]; then
			rm -f "${CONF_PKG_S3["$_S3"]}/$CONF_GIT_MAIN"
			FOUND_MAIN_LINK=1
		fi
		# copy files to Amazon S3
		dpk_echo "$(ansi dim)> $_S3$(ansi reset)"
		# check if the static files (in this path) must be compressed
		if [ "$CONF_PKG_S3_COMPRESS" != "1" ]; then
			# no compression, copy files in bulk
			aws s3 sync "${CONF_PKG_S3["$_S3"]}" "s3://${_S3}/${DPK_OPT["tag"]}" --acl public-read --cache-control "max-age=31536000" || _pkg_s3_fail
		else
			# process files one by one, to compress text files before sending to Amazon S3
			# move to the source path
			pushd "${CONF_PKG_S3["$_S3"]}" > /dev/null || _pkg_s3_fail
			# loop on the files to compress them (only text files) and send them to Amazon S3
			while read -r _FILE; do
				MUST_COMPRESS=1
				# remove "./" at the beginning of the file name
				_FILE="${_FILE#./}"
				# check if it's a text file
				if ! _pkg_s3_is_text "$_FILE"; then
					# it's not a text file => don't compress it
					MUST_COMPRESS=0
				else
					# it's a text file
					# don't send the file if another file exists with the same name + ".gz" suffix
					if [ -e "$_FILE.gz" ]; then
						continue
					fi
					# don't compress small files and gzip files
					if [ "$(wc -c < "$_FILE")" -lt $_PKG_S3_COMPRESS_MIN_SIZE ] || [ "${_FILE: -3}" = ".gz" ]; then
						MUST_COMPRESS=0
					fi
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
					# the gzip'ed version of the file has just been created
					# => sen the gzip'ed version without the ".gz" name suffix, but with a "gzip" content encoding
					aws s3 cp "$_SRC" "s3://${_S3}/${DPK_OPT["tag"]}/${_FILE}" --acl public-read --content-encoding gzip  --cache-control "max-age=31536000"
					_STATUS=$?
					# delete the gzip'ed file
					rm -f "${_FILE}.gz"
					if [ $_STATUS -ne 0 ]; then
						_pkg_s3_fail
					fi
				elif [ "${_FILE: -3}" = ".gz" ] && [ -e "${_FILE:0:-3}" ]; then
					# it's a gzip file, and the not-gzip'ed version exists
					if _pkg_s3_is_text "${_FILE:0:-3}"; then
						# the not-gzip'ed version is a text file
						# => send the gzip file without the ".gz" name suffix, but with a "gzip" content-encoding
						aws s3 cp "$_SRC" "s3://${_S3}/${DPK_OPT["tag"]}/${_FILE:0:-3}" --acl public-read --content-encoding gzip --cache-control "max-age=31536000" || _pkg_s3_fail
					else
						# raw file => send as is
						aws s3 cp "$_SRC" "s3://${_S3}/${DPK_OPT["tag"]}/${_FILE}" --acl public-read --cache-control "max-age=31536000" || _pkg_s3_fail
					fi
				else
					# raw file => send as is
					aws s3 cp "$_SRC" "s3://${_S3}/${DPK_OPT["tag"]}/${_FILE}" --acl public-read --cache-control "max-age=31536000" || _pkg_s3_fail
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
			abort "$(ansi red)The URL $(ansi reset)$(ansi dim)$CONF_PKG_CHECK_URL$(ansi reset) $(ansi red)is returning an error.$(ansi reset)" $DPK_EXIT_ENV_URL
		fi
	fi
}


#!/usr/bin/env bash

# "install" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="install"

# Rule's section (for documentation).
RULE_SECTION="Tag management"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="platform tag no-apache no-crontab no-systemd no-supervisor no-xinetd no-db-migration"

# Definition of configuration associative arrays.
declare -A CONF_INSTALL_SYMLINK
declare -A CONF_INSTALL_CHOWN
declare -A CONF_INSTALL_CHGRP
declare -A CONF_INSTALL_CHMOD

# Global variables shared between functions, set by rule_exec_install() and given as parameters
# to the pre/post-install and pre/post-config scripts (see the _install_pre_scripts(),
# _install_post_scripts(), _config_pre_scripts() and _config_post_scripts() functions):
# the tag or branch which was deployed before the installation...
CURRENT_TAG=""
# ...and the direction of the version change ("+" if the newly installed tag is more recent
# than the previously installed one, "-" otherwise).
TAG_EVOLUTION=""

# Show help for this rule.
rule_help_install() {
	echo "   dpk $(ansi bold)install$(ansi reset) $(ansi dim)[--$(ansi reset)platform$(ansi dim)=dev|test|prod] [$(ansi reset)--tag$(ansi dim)=$CONF_GIT_MAIN|X.Y.Z] [$(ansi reset)--no-apache$(ansi dim)] [$(ansi reset)--no-crontab$(ansi dim)] [$(ansi reset)--no-systemd$(ansi dim)] [$(ansi reset)--no-supervisor$(ansi dim)] [$(ansi reset)--no-xinetd$(ansi dim)] [$(ansi reset)--no-db-migration$(ansi dim)]$(ansi reset)"
	echo "       $(ansi dim)Deploy source code (pull tag from GitHub, generate files, set files rights).$(ansi reset)"
	echo "       --platform        $(ansi dim)Definition of the current platform. Otherwise, Dispak will try to detect it.$(ansi reset)"
	echo "       --tag             $(ansi dim)Tag to install (or $(ansi reset)$CONF_GIT_MAIN$(ansi dim) to use its last revision). Otherwise, the last tagged version will be installed.$(ansi reset)"
	echo "       --no-apache       $(ansi dim)Don't install Apache configuration files, even if Apache is installed on the current machine.$(ansi reset)"
	echo "       --no-crontab      $(ansi dim)Don't install crontab configuration.$(ansi reset)"
	echo "       --no-systemd      $(ansi dim)Don't install systemd daemon configurations.$(ansi reset)"
	echo "       --no-supervisor   $(ansi dim)Don't install supervisor daemon configurations.$(ansi reset)"
	echo "       --no-xinetd       $(ansi dim)Don't install xinetd configuration.$(ansi reset)"
	echo "       --no-db-migration $(ansi dim)Don't perform database migration.$(ansi reset)"
	echo "       $(ansi yellow)⚠ Needs sudo rights$(ansi reset)"
}

# Execution of the rule
rule_exec_install() {
	local TAG_MAJOR TAG_MINOR TAG_REVISION CURRENT_TAG_MAJOR CURRENT_TAG_MINOR CURRENT_TAG_REVISION _SYMLINK
	check_git
	check_sudo
	check_tag
	check_platform
	# chunk the new tag number
	TAG_MAJOR=$(echo "${DPK_OPT["tag"]}" | cut -d"." -f 1)
	TAG_MINOR=$(echo "${DPK_OPT["tag"]}" | cut -d"." -f 2)
	TAG_REVISION=$(echo "${DPK_OPT["tag"]}" | cut -d"." -f 3)
	# get currently installed version number
	CURRENT_TAG="$(git_get_current_tag)"
	if [ "$CURRENT_TAG" != "" ] && [[ "$CURRENT_TAG" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
		CURRENT_TAG_MAJOR=$(echo "$CURRENT_TAG" | cut -d"." -f 1)
		CURRENT_TAG_MINOR=$(echo "$CURRENT_TAG" | cut -d"." -f 2)
		CURRENT_TAG_REVISION=$(echo "$CURRENT_TAG" | cut -d"." -f 3)
		TAG_EVOLUTION="+"
		if [ $TAG_MAJOR -lt $CURRENT_TAG_MAJOR ]; then
			TAG_EVOLUTION="-"
		elif [ $TAG_MAJOR -eq $CURRENT_TAG_MAJOR ] && [ $TAG_MINOR -lt $CURRENT_TAG_MINOR ]; then
			TAG_EVOLUTION="-"
		elif [ $TAG_MAJOR -eq $CURRENT_TAG_MAJOR ] && [ $TAG_MINOR -eq $CURRENT_TAG_MINOR ] && [ $TAG_REVISION -lt $CURRENT_TAG_REVISION ]; then
			TAG_EVOLUTION="-"
		fi
	fi
	# check that only stable tag is installed on production servers
	if [ "${DPK_OPT["platform"]}" = "prod" ]; then
		if [ "$(($TAG_MINOR % 2))" != "0" ]; then
			abort "$(ansi red)It's forbidden to install $(ansi reset)unstable$(ansi red) tags on production server.$(ansi reset)" $DPK_EXIT_USAGE_VALUE
		fi
	fi
	# get the tag's configuration file
	if [ -f "$GIT_REPO_PATH/etc/dispak.conf" ]; then
		git checkout "${DPK_OPT["tag"]}" -- "$GIT_REPO_PATH/etc/dispak.conf"
		if [ $? -ne 0 ]; then
			abort "$(ansi red)Unable to checkout file $(ansi reset)etc/dispak.conf$(ansi red) from tag $(ansi reset)${DPK_OPT["tag"]}" $DPK_EXIT_GIT
		fi
		# read the tag's configuration file
		. "$(eval realpath "$GIT_REPO_PATH/etc/dispak.conf")"
		# reset the configuration file
		git restore --staged --worktree "$GIT_REPO_PATH/etc/dispak.conf"
	fi
	# get the currently deployed branch or tag (used as parameter of pre/post scripts)
	CURRENT_TAG="$(git symbolic-ref -q --short HEAD || git describe --tags --exact-match)"
	# remove version-named symlinks created by previous deployments
	for _SYMLINK in ${!CONF_INSTALL_SYMLINK[@]}; do
		_install_clean_version_links "$_SYMLINK" "" ""
	done
	# remove version alias links created by previous deployments
	_install_version_alias_cleanup
	# execute pre-install scripts
	_install_pre_scripts
	# execute pre-config scripts
	_config_pre_scripts
	# deploy source code
	git_fetch
	echo "$(ansi bold)Updating source code repository$(ansi reset)"
	if [ "${DPK_OPT["tag"]}" = "$CONF_GIT_MAIN" ]; then
		if ! git checkout "$CONF_GIT_MAIN" --quiet ; then
			abort "$(ansi red)Failed to move back to '$CONF_GIT_MAIN' branch.$(ansi reset)" $DPK_EXIT_GIT
		fi
	else
		if ! git checkout "tags/${DPK_OPT["tag"]}" --quiet ; then
			abort "$(ansi red)Failed to update repository to tag '${DPK_OPT["tag"]}'.$(ansi reset)" $DPK_EXIT_GIT
		fi
	fi
	# database migration (executed right after the code deployment and before any system
	# configuration: if a migration fails, the installation stops while the machine
	# configuration is still untouched)
	_install_db_migration
	# create symlinks (named with the tag number, or the main branch's name)
	for _SYMLINK in ${!CONF_INSTALL_SYMLINK[@]}; do
		if [ -e "$_SYMLINK/${DPK_OPT["tag"]}" ] || [ -L "$_SYMLINK/${DPK_OPT["tag"]}" ]; then
			# a committed link or file already uses this name
			continue
		fi
		echo "$(ansi bold)Create symlink $(ansi reset)$(ansi dim)$_SYMLINK/${DPK_OPT["tag"]}$(ansi reset)"
		ln -sn "${CONF_INSTALL_SYMLINK["$_SYMLINK"]}" "$_SYMLINK/${DPK_OPT["tag"]}"
	done
	# create version alias links
	_install_version_alias
	# install crontab
	_install_crontab
	# Apache configuration
	_install_config_apache
	# xinetd configuration
	_install_xinetd
	# files configuration
	_install_config_files
	# supervisor configuration
	_install_supervisor
	# systemd configuration
	_install_systemd
	# execute post-config scripts
	_config_post_scripts
	# execute post-install scripts
	_install_post_scripts
}

# _install_pre_scripts()
# Execute pre-install scripts.
_install_pre_scripts() {
	local _SCRIPT _EXEC
	if [ "$CONF_INSTALL_SCRIPTS_PRE" = "" ]; then
		return
	fi
	echo "$(ansi bold)Execute pre-install scripts$(ansi reset)"
	for _SCRIPT in $CONF_INSTALL_SCRIPTS_PRE; do
		_SCRIPT="$(echo $_SCRIPT | sed 's/#/ /')"
		_EXEC="$(echo "$_SCRIPT" | cut -d" " -f 1)"
		echo "> $(ansi dim)$_SCRIPT$(ansi reset)"
		if [ ! -x "$_EXEC" ]; then
			chmod +x "$_EXEC"
		fi
		$_SCRIPT "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}" "$CURRENT_TAG" "$TAG_EVOLUTION"
		if [ $? -ne 0 ]; then
			abort "$(ansi red)Execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_INSTALL_PRE
		fi
	done
	echo "$(ansi gree)Done$(ansi reset)"
}

# _install_post_scripts()
# Execute post-install scripts.
_install_post_scripts() {
	local _SCRIPT _EXEC
	if [ "$CONF_INSTALL_SCRIPTS_POST" = "" ]; then
		return
	fi
	echo "$(ansi bold)Execute post-install scripts$(ansi reset)"
	for _SCRIPT in $CONF_INSTALL_SCRIPTS_POST; do
		_SCRIPT="$(echo $_SCRIPT | sed 's/#/ /')"
		_EXEC="$(echo "$_SCRIPT" | cut -d" " -f 1)"
		echo "> $(ansi dim)$_SCRIPT$(ansi reset)"
		if [ ! -x "$_EXEC" ]; then
			chmod +x "$_EXEC"
		fi
		$_SCRIPT "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}" "$CURRENT_TAG" "$TAG_EVOLUTION"
		if [ $? -ne 0 ]; then
			abort "$(ansi red)Execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_INSTALL_POST
		fi
	done
	echo "$(ansi gree)Done$(ansi reset)"
}

# _install_clean_version_links()
# Remove the symbolic links of a directory which names contain a version number
# (or the main branch's name) and that are not committed.
# @param	string	Path to the directory to process.
# @param	string	Prefix of the links' names (may be empty).
# @param	string	Suffix of the links' names (may be empty).
_install_clean_version_links() {
	local _VLINK _VPART
	for _VLINK in "$1/$2"*"$3"; do
		# this test must stay the first instruction of the loop: it absorbs the
		# literal pattern given by bash when the glob matches nothing
		if [ ! -L "$_VLINK" ]; then
			continue
		fi
		# extract the version part of the link's name
		_VPART="${_VLINK##*/}"
		_VPART="${_VPART#"$2"}"
		_VPART="${_VPART%"$3"}"
		if ! [[ "$_VPART" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$_VPART" != "$CONF_GIT_MAIN" ]; then
			continue
		fi
		# committed links are never removed
		if git ls-files --error-unmatch -- "$_VLINK" > /dev/null 2>&1; then
			continue
		fi
		echo "$(ansi bold)Removing symlink $(ansi reset)$(ansi dim)$_VLINK$(ansi reset)"
		rm -f "$_VLINK"
	done
}

# _install_version_alias_cleanup()
# Remove the version alias links created by previous deployments.
_install_version_alias_cleanup() {
	local _ALIAS _ALIAS_DIR _ALIAS_BASE
	if [ "$CONF_INSTALL_VERSION_ALIAS" = "" ]; then
		return
	fi
	for _ALIAS in $CONF_INSTALL_VERSION_ALIAS; do
		_ALIAS_DIR="$(dirname "$_ALIAS")"
		_ALIAS_BASE="$(basename "$_ALIAS")"
		# version added at the end of the name (directories, files without extension)
		_install_clean_version_links "$_ALIAS_DIR" "${_ALIAS_BASE}-" ""
		# version added before the file's extension
		if [[ "${_ALIAS_BASE:1}" == *.* ]]; then
			_install_clean_version_links "$_ALIAS_DIR" "${_ALIAS_BASE%.*}-" ".${_ALIAS_BASE##*.}"
		fi
	done
}

# _install_version_alias()
# Create version alias links: for each listed file or directory, a symbolic link
# which name contains the installed version number (or the main branch's name).
_install_version_alias() {
	local _ALIAS _ALIAS_DIR _ALIAS_BASE _ALIAS_LINK
	if [ "$CONF_INSTALL_VERSION_ALIAS" = "" ]; then
		return
	fi
	# the version must be a tag number or the main branch's name
	if ! [[ "${DPK_OPT["tag"]}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "${DPK_OPT["tag"]}" != "$CONF_GIT_MAIN" ]; then
		warn "Tag '$(ansi dim)${DPK_OPT["tag"]}$(ansi reset)' doesn't match the X.Y.Z format, no version alias created."
		return
	fi
	echo "$(ansi bold)Create version alias links$(ansi reset)"
	for _ALIAS in $CONF_INSTALL_VERSION_ALIAS; do
		# check the aliased element exists
		if [ ! -e "$_ALIAS" ] && [ ! -L "$_ALIAS" ]; then
			warn "Unable to find '$(ansi dim)$_ALIAS$(ansi reset)', no alias created."
			continue
		fi
		_ALIAS_DIR="$(dirname "$_ALIAS")"
		_ALIAS_BASE="$(basename "$_ALIAS")"
		# compute the link's name
		if [ -d "$_ALIAS" ] || [[ "${_ALIAS_BASE:1}" != *.* ]]; then
			# directory, file without extension or dot file: version added at the end
			_ALIAS_LINK="$_ALIAS_DIR/${_ALIAS_BASE}-${DPK_OPT["tag"]}"
		else
			# file: version added before the extension
			_ALIAS_LINK="$_ALIAS_DIR/${_ALIAS_BASE%.*}-${DPK_OPT["tag"]}.${_ALIAS_BASE##*.}"
		fi
		# create the link, unless its name is already used (committed link or file)
		if [ -e "$_ALIAS_LINK" ] || [ -L "$_ALIAS_LINK" ]; then
			continue
		fi
		echo "$(ansi dim)> $_ALIAS_LINK$(ansi reset)"
		ln -sn "$_ALIAS_BASE" "$_ALIAS_LINK"
		if [ $? -ne 0 ]; then
			abort "Unable to create the symlink '$(ansi dim)$_ALIAS_LINK$(ansi reset)'." $DPK_EXIT_ENV
		fi
	done
}

# _install_crontab()
# Install new crontab file.
_install_crontab() {
	local START_MARK END_MARK BEGIN_GEN END_GEN
	if [ -v DPK_OPT["no-crontab"] ]; then
		return
	fi
	if [ ! -f "$GIT_REPO_PATH/etc/crontab" ] && [ ! -f "$GIT_REPO_PATH/etc/crontab.gen" ]; then
		return
	fi
	echo "$(ansi bold)Installing crontab$(ansi reset)"
	if [ -e "$GIT_REPO_PATH/etc/crontab.gen" ]; then
		echo -n "$(ansi dim)+ Generating... $(ansi reset)"
		chmod +x "$GIT_REPO_PATH/etc/crontab.gen"
		"$GIT_REPO_PATH/etc/crontab.gen" "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}" > "$GIT_REPO_PATH/etc/crontab"
		if [ $? -ne 0 ]; then
			echo
			abort "$(ansi red)Crontab configuration generation script $(ansi reset)$GIT_REPO_PATH/etc/crontab.gen$(ansi red) execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_GENERATOR
		fi
		echo "$(ansi green)done$(ansi reset)"
	fi
	START_MARK="# ┏━━━━━┥DISPAK CRONTAB START┝━━━┥$GIT_REPO_PATH/etc/crontab┝━━━━━┓"
	END_MARK="# ┗━━━━━┥DISPAK CRONTAB END┝━━━━━┥$GIT_REPO_PATH/etc/crontab┝━━━━━┛"
	echo "$(crontab -l 2>/dev/null)" | grep "^$START_MARK$" > /dev/null
	if [ $? -ne 0 ]; then
		(crontab -l 2>/dev/null; echo; echo $START_MARK; echo; cat "$GIT_REPO_PATH/etc/crontab"; echo $END_MARK) | crontab -
	else
		BEGIN_GEN=$(crontab -l 2>/dev/null | grep -n "$START_MARK" | sed 's/\(.*\):.*/\1/g')
		END_GEN=$(crontab -l 2>/dev/null | grep -n "$END_MARK" | sed 's/\(.*\):.*/\1/g')
		(crontab -l 2>/dev/null | head -n $BEGIN_GEN; echo; cat "$GIT_REPO_PATH/etc/crontab"; crontab -l 2>/dev/null | tail -n +$END_GEN) | crontab -
	fi
	echo "$(ansi green)Done$(ansi reset)"
}

# _install_xinetd()
# Install new xinetd file.
_install_xinetd() {
	local START_MARK END_MARK BEGIN_GEN END_GEN XINETD_TMP_FILE
	if [ -v DPK_OPT["no-xinetd"] ]; then
		return
	fi
	if [ ! -f "$GIT_REPO_PATH/etc/xinetd" ] && [ ! -f "$GIT_REPO_PATH/etc/xinetd.gen" ]; then
		return
	fi
	echo "$(ansi bold)Installing xinetd configuration$(ansi reset)"
	if [ ! -e /etc/xinetd.d/dispak ]; then
		sudo touch /etc/xinetd.d/dispak
		sudo chmod 644 /etc/xinetd.d/dispak
	fi
	if [ -e "$GIT_REPO_PATH/etc/xinetd.gen" ]; then
		echo -n "$(ansi dim)+ Generating... $(ansi reset)"
		chmod +x "$GIT_REPO_PATH/etc/xinetd.gen"
		"$GIT_REPO_PATH/etc/xinetd.gen" "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}" > "$GIT_REPO_PATH/etc/xinetd"
		if [ $? -ne 0 ]; then
			echo
			abort "$(ansi red)Xinetd configuration generation script $(ansi reset)$GIT_REPO_PATH/etc/xinetd.gen$(ansi red) execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_GENERATOR
		fi
		echo "$(ansi green)done$(ansi reset)"
	fi
	START_MARK="# ┏━━━━━┥DISPAK XINETD START┝━━━┥$GIT_REPO_PATH/etc/xinetd┝━━━━━┓"
	END_MARK="# ┗━━━━━┥DISPAK XINETD END┝━━━━━┥$GIT_REPO_PATH/etc/xinetd┝━━━━━┛"
	sudo cat /etc/xinetd.d/dispak | grep "^$START_MARK$" > /dev/null
	if [ $? -ne 0 ]; then
		sudo bash -c "(echo; echo \"$START_MARK\"; cat \"$GIT_REPO_PATH/etc/xinetd\"; echo \"$END_MARK\") >> /etc/xinetd.d/dispak"
	else
		BEGIN_GEN=$(cat /etc/xinetd.d/dispak | grep -n "$START_MARK" | sed 's/\(.*\):.*/\1/g')
		END_GEN=$(cat /etc/xinetd.d/dispak | grep -n "$END_MARK" | sed 's/\(.*\):.*/\1/g')
		XINETD_TMP_FILE="$(sudo mktemp --tmpdir=/tmp dispak-xinetd.XXXXXXXXXX)"
		sudo bash -c "(cat /etc/xinetd.d/dispak | head -n $BEGIN_GEN > $XINETD_TMP_FILE; cat \"$GIT_REPO_PATH/etc/xinetd\" >> $XINETD_TMP_FILE; cat /etc/xinetd.d/dispak | tail -n +$END_GEN >> $XINETD_TMP_FILE)"
		sudo bash -c "cat $XINETD_TMP_FILE > /etc/xinetd.d/dispak"
		sudo rm $XINETD_TMP_FILE
	fi
	echo "$(ansi green)Done$(ansi reset)"
}

# _install_supervisor()
# Install new Supervisor files.
_install_supervisor() {
	local CONFIG_FOUND FILENAME DEST
	if [ -v DPK_OPT["no-supervisor"] ]; then
		return
	fi
	if [ ! -d "$GIT_REPO_PATH/etc/supervisor" ]; then
		return
	fi
	echo "$(ansi bold)Installing Supervisor configuration$(ansi reset)"
	if [ ! -d /etc/supervisor/conf.d ]; then
		echo
		abort "$(ansi red)Unable to find directory $(ansi reset)/etc/supervisor/conf.d" $DPK_EXIT_ENV
	fi
	CONFIG_FOUND=0
	for FILENAME in $GIT_REPO_PATH/etc/supervisor/*; do
		if [[ "$FILENAME" == *.conf.gen ]]; then
			DEST="/etc/supervisor/conf.d/$(basename "${FILENAME::-4}")"
			echo -n "$(ansi dim)+ Generating$(ansi reset) $DEST "
			chmod +x "$FILENAME"
			sudo bash -c "\"$FILENAME\" \"${DPK_OPT["platform"]}\" \"${DPK_OPT["tag"]}\" > \"$DEST\""
			if [ $? -ne 0 ]; then
				echo
				abort "$(ansi red)Supervisor configuration generation script $(ansi reset)$FILENAME$(ansi red) execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_GENERATOR
			fi
			echo "$(ansi green)done$(ansi reset)"
			CONFIG_FOUND=1
		elif [[ "$FILENAME" == *.conf ]]; then
			DEST="/etc/supervisor/conf.d/$(basename "$FILENAME")"
			echo -n "$(ansi dim)+ Copying $(ansi reset) $DEST "
			if ! sudo cp "$FILENAME" "$DEST"; then
				echo
				abort "$(ansi red)Unable to copy file $(ansi reset)$FILENAME$(ansi red) to $(ansi reset)$DEST$(ansi red).$(ansi reset)" $DPK_EXIT_ENV
			fi
			echo "$(ansi green)done$(ansi reset)"
			CONFIG_FOUND=1
		fi
	done
	if [ $CONFIG_FOUND -eq 1 ]; then
		echo "$(ansi dim)+ Restarting Supervisor$(ansi reset)"
		if ! sudo supervisorctl reread || ! sudo supervisorctl update; then
			abort "$(ansi red)Unable to restart Supervisor.$(ansi reset)" $DPK_EXIT_ENV
		fi
		echo "$(ansi green)Done$(ansi reset)"
	fi
}

# _install_systemd
# Install new systemd files.
_install_systemd() {
	local FILENAME SERVICE_NAME SERVICE_FILE DEST DEST_SERVICE
	if [ -v DPK_OPT["no-systemd"] ]; then
		return
	fi
	if [ ! -d "$GIT_REPO_PATH/etc/systemd" ]; then
		return
	fi
	echo "$(ansi bold)Installing systemd configuration$(ansi reset)"
	if [ ! -d /etc/systemd/system ]; then
		echo
		abort "$(ansi red)Unable to find directory $(ansi reset)/etc/systemd/system" $DPK_EXIT_ENV
	fi
	for FILENAME in $GIT_REPO_PATH/etc/systemd/*; do
		SERVICE_NAME=""
		if [[ "$FILENAME" == *.target.gen ]]; then
			# target - generate
			SERVICE_NAME="$(basename "${FILENAME::-11}")"
			echo -n "$(ansi dim)+ Add target$(ansi reset) $SERVICE_NAME "
			SERVICE_FILE="$GIT_REPO_PATH/etc/systemd/$SERVICE_NAME@.service"
			# check associated "@.service" file
			if [ ! -f "$SERVICE_FILE" ] || [ ! -f "$SERVICE_FILE.gen" ]; then
				echo
				abort "$(ansi red)Unable to find file$(ansi reset) $SERVICE_FILE" $DPK_EXIT_ENV
			fi
			# generate target file
			DEST="/etc/systemd/system/$(basename "${FILENAME::-4}")"
			echo -n "$(ansi dim)+ Generating$(ansi reset) $DEST "
			chmod +x "$FILENAME"
			sudo bash -c "\"$FILENAME\" \"${DPK_OPT["platform"]}\" \"${DPK_OPT["tag"]}\" > \"$DEST\""
			if [ $? -ne 0 ]; then
				echo
				abort "$(ansi red)Systemd configuration generation script $(ansi reset)$FILENAME$(ansi red) execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_GENERATOR
			fi
			if [ ! -s "$DEST" ]; then
				echo "$(ansi yellow)empty$(ansi reset)"
				sudo rm -f "$DEST"
				continue
			fi
			echo "$(ansi green)done$(ansi reset)"
			# process associated "@.service" file
			DEST_SERVICE="/etc/systemd/system/$SERVICE_NAME@.service"
			if [ -f "$SERVICE_FILE.gen" ]; then
				# generate
				echo -n "$(ansi dim)+ Generating$(ansi reset) $DEST_SERVICE "
				chmod +x "$SERVICE_FILE.gen"
				sudo bash -c "\"$SERVICE_FILE.gen\" \"${DPK_OPT["platform"]}\" \"${DPK_OPT["tag"]}\" > \"$DEST_SERVICE\""
				if [ $? -ne 0 ]; then
					echo
					sudo rm -f "$DEST"
					abort "$(ansi red)Systemd configuration generation script $(ansi reset)$SERVICE_FILE.gen$(ansi red) execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_GENERATOR
				fi
				if [ ! -s "$DEST_SERVICE" ]; then
					echo "$(ansi yellow)empty$(ansi reset)"
					sudo rm -f "$DEST" "$DEST_SERVICE"
					continue
				fi
				echo "$(ansi green)done$(ansi reset)"
			else
				# copy
				if ! sudo cp "$SERVICE_FILE" /etc/systemd/system; then
					echo
					rm -f "$DEST"
					abort "$(ansi red)Unable to copy file$(ansi reset) $SERVICE_FILE $(ansi red)to$(ansi reset) $DEST_SERVICE" $DPK_EXIT_ENV
				fi
			fi
			SERVICE_NAME="$SERVICE_NAME.target"
		elif [[ "$FILENAME" == *.target ]]; then
			# target - copy
			SERVICE_NAME="$(basename "${FILENAME::-7}")"
			echo -n "$(ansi dim)+ Add target$(ansi reset) $SERVICE_NAME "
			SERVICE_FILE="$GIT_REPO_PATH/etc/systemd/$SERVICE_NAME@.service"
			if [ ! -f "$SERVICE_FILE" ]; then
				echo
				abort "$(ansi red)Unable to find file$(ansi reset) $SERVICE_FILE" $DPK_EXIT_ENV
			fi
			if ! sudo cp "$FILENAME" /etc/systemd/system/; then
				echo
				abort "$(ansi red)Unable to copy file$(ansi reset) $FILENAME $(ansi red)to$(ansi reset) /etc/systemd/system/$SERVICE_NAME.target" $DPK_EXIT_ENV
			fi
			# process associated "@.service" file
			DEST_SERVICE="/etc/systemd/system/$SERVICE_NAME@.service"
			if [ -f "$SERVICE_FILE.gen" ]; then
				# generate
				echo -n "$(ansi dim)+ Generating$(ansi reset) $DEST_SERVICE "
				chmod +x "$SERVICE_FILE.gen"
				sudo bash -c "\"$SERVICE_FILE.gen\" \"${DPK_OPT["platform"]}\" \"${DPK_OPT["tag"]}\" > \"$DEST_SERVICE\""
				if [ $? -ne 0 ]; then
					echo
					abort "$(ansi red)Systemd configuration generation script $(ansi reset)$SERVICE_FILE.gen$(ansi red) execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_GENERATOR
				fi
				if [ ! -s "$DEST_SERVICE" ]; then
					echo "$(ansi yellow)empty$(ansi reset)"
					sudo rm -f "$DEST" "$DEST_SERVICE"
					continue
				fi
				echo "$(ansi green)done$(ansi reset)"
			else
				# copy
				if ! sudo cp "$SERVICE_FILE" /etc/systemd/system; then
					echo
					rm -f "/etc/systemd/system/$SERVICE_NAME.target"
					abort "$(ansi red)Unable to copy file$(ansi reset) $SERVICE_FILE $(ansi red)to$(ansi reset) $DEST_SERVICE" $DPK_EXIT_ENV
				fi
			fi
			SERVICE_NAME="$SERVICE_NAME.target"
		elif [[ "$FILENAME" == *.service.gen ]] && [[ "$FILENAME" != *@.service.gen ]]; then
			# service - generate
			SERVICE_NAME="$(basename "${FILENAME::-12}")"
			DEST="/etc/systemd/system/$SERVICE_NAME.service"
			echo -n "$(ansi dim)+ Generating$(ansi reset) $DEST"
			sudo bash -c "\"$FILENAME\" \"${DPK_OPT["platform"]}\" \"${DPK_OPT["tag"]}\" > \"$DEST\""
			if [ $? -ne 0 ]; then
				echo
				abort "$(ansi red)Systemd configuration generation script $(ansi reset)$FILENAME$(ansi red) execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_GENERATOR
			fi
			if [ ! -s "$DEST" ]; then
				echo "$(ansi yellow)empty$(ansi reset)"
				sudo rm -f "$DEST"
				continue
			fi
			echo "$(ansi green)done$(ansi reset)"
		elif [[ "$FILENAME" == *.service ]] && [[ "$FILENAME" != *@.service ]]; then
			# service - copy
			SERVICE_NAME="$(basename "${FILENAME::-8}")"
			echo -n "$(ansi dim)+ Add service$(ansi reset) $SERVICE_NAME "
			if ! sudo cp "$FILENAME" /etc/systemd/system/; then
				echo
				abort "$(ansi red)Unable to copy file$(ansi reset) $FILENAME $(ansi red)to$(ansi reset) /etc/systemd/system/$SERVICE_NAME.service" $DPK_EXIT_ENV
			fi
		fi
		if [ "$SERVICE_NAME" != "" ]; then
			if ! sudo systemctl stop $SERVICE_NAME; then
				echo
				echo "$(ansi red)Unable to stop service$(ansi reset) $SERVICE_NAME $(ansi red).$(ansi reset)"
			elif ! sudo systemctl daemon-reload; then
				echo
				echo "$(ansi red)Systemd is unable to reload the daemon configuration files.$(ansi reset)"
			elif ! sudo systemctl enable $SERVICE_NAME; then
				echo
				echo "$(ansi red)Unable to enable server$(ansi reset) $SERVICE_NAME $(ansi red).$(ansi reset)"
			elif ! sudo systemctl start $SERVICE_NAME; then
				echo
				echo "$(ansi red)Unable to start service$(ansi reset) $SERVICE_NAME $(ansi red).$(ansi reset)"
			else
				echo "$(ansi green)done$(ansi reset)"
			fi
		fi
	done
}

# _install_db_query()
# Execute SQL statements on the configured database server, and print the raw result
# (without the column headers). Return the mysql client exit status.
# @param	string	The SQL statements to execute.
_install_db_query() {
	echo "$1" | MYSQL_PWD="$CONF_DB_PWD" mysql --skip-column-names -u "$CONF_DB_USER" -h "$CONF_DB_HOST" -P "$CONF_DB_PORT" 2> /dev/null
}

# _install_db_migration()
# Do the migration of a new version of the database.
# The database connection is checked first. Each migration file is executed inside a
# transaction (with a MySQL limitation: DDL statements generate implicit commits, so only
# pure-DML migrations are atomic). If a migration fails, the installation is aborted with
# the MySQL error message: the migration is not marked as done (its tracking row is kept
# with a NULL dbm_d_done field, and the error message is stored in its dbm_s_error column),
# so it will be executed again at the next install, with a new tracking row.
_install_db_migration() {
	local ERROR_COLUMN MIGRATION MIGRATION_FILE NBR MIGRATION_ID OUTPUT ERROR_SQL
	if [ ! -d "$GIT_REPO_PATH/etc/database/migrations" ] || [ -v DPK_OPT["no-db-migration"] ] || [ "$CONF_DB_HOST" = "" ] || [ "$CONF_DB_PORT" = "" ] || [ "$CONF_DB_USER" = "" ] || [ "$CONF_DB_PWD" = "" ] || [ "$CONF_DB_MIGRATION_BASE" = "" ] || [ "$CONF_DB_MIGRATION_TABLE" = "" ]; then
		return
	fi
	echo "$(ansi bold)Database migration$(ansi reset)"
	# check the database connection
	check_dbhost
	# check the migration table has the error storage column, otherwise try to add it
	ERROR_COLUMN=1
	if [ "$(_install_db_query "SHOW COLUMNS FROM $CONF_DB_MIGRATION_BASE.$CONF_DB_MIGRATION_TABLE LIKE 'dbm_s_error'")" = "" ]; then
		if ! _install_db_query "ALTER TABLE $CONF_DB_MIGRATION_BASE.$CONF_DB_MIGRATION_TABLE ADD COLUMN dbm_s_error TEXT DEFAULT NULL" > /dev/null; then
			warn "$(ansi yellow)Unable to add the '$(ansi reset)dbm_s_error$(ansi yellow)' column to the migration table (missing ALTER privilege?). Migration error messages will not be stored in the database.$(ansi reset)"
			ERROR_COLUMN=0
		fi
	fi
	# loop on migration files
	for MIGRATION in $(ls "$GIT_REPO_PATH/etc/database/migrations" | grep -v current | sort -V); do
		MIGRATION_FILE="$GIT_REPO_PATH/etc/database/migrations/$MIGRATION"
		# check if the migration was already processed
		NBR="$(_install_db_query "SELECT COUNT(*) FROM $CONF_DB_MIGRATION_BASE.$CONF_DB_MIGRATION_TABLE WHERE dbm_s_version = '$MIGRATION' AND dbm_d_done IS NOT NULL")"
		if ! [[ "$NBR" =~ ^[0-9]+$ ]]; then
			abort "$(ansi red)Unable to get the status of the migration file $(ansi reset)$MIGRATION_FILE$(ansi red).$(ansi reset)" $DPK_EXIT_DB_TRACKING
		fi
		if [ "$NBR" != "0" ]; then
			continue
		fi
		echo "$(ansi dim)Executing database migration file $(ansi blue)$MIGRATION_FILE$(ansi reset)"
		# create the tracking row of this migration attempt
		MIGRATION_ID="$(_install_db_query "INSERT INTO $CONF_DB_MIGRATION_BASE.$CONF_DB_MIGRATION_TABLE SET dbm_d_creation = NOW(), dbm_s_version = '$MIGRATION'; SELECT LAST_INSERT_ID()")"
		if ! [[ "$MIGRATION_ID" =~ ^[0-9]+$ ]]; then
			abort "$(ansi red)Unable to create the tracking row of the migration file $(ansi reset)$MIGRATION_FILE$(ansi red).$(ansi reset)" $DPK_EXIT_DB_TRACKING
		fi
		# execute the migration file inside a transaction
		# (DDL statements are not transactional in MySQL: they generate implicit commits)
		OUTPUT="$({ echo "START TRANSACTION;"; cat "$MIGRATION_FILE"; echo; echo "COMMIT;"; } | MYSQL_PWD="$CONF_DB_PWD" mysql --skip-column-names -u "$CONF_DB_USER" -h "$CONF_DB_HOST" -P "$CONF_DB_PORT" 2>&1)"
		if [ $? -ne 0 ]; then
			# the migration failed: display the MySQL error, store it in the tracking row
			# (which keeps a NULL dbm_d_done field, so the migration will be executed again
			# at the next install, with a new tracking row), and stop the installation
			echo "$OUTPUT"
			if [ $ERROR_COLUMN -eq 1 ]; then
				ERROR_SQL="${OUTPUT//\\/\\\\}"
				ERROR_SQL="${ERROR_SQL//\'/\\\'}"
				_install_db_query "UPDATE $CONF_DB_MIGRATION_BASE.$CONF_DB_MIGRATION_TABLE SET dbm_s_error = '$ERROR_SQL' WHERE dbm_i_id = '$MIGRATION_ID'" > /dev/null
			fi
			abort "$(ansi red)The migration file $(ansi reset)$MIGRATION_FILE$(ansi red) failed. It is not marked as done and will be executed again at the next install; the statements executed before the error may still be applied.$(ansi reset)" $DPK_EXIT_DB_MIGRATION
		fi
		# mark the migration as done
		if ! _install_db_query "UPDATE $CONF_DB_MIGRATION_BASE.$CONF_DB_MIGRATION_TABLE SET dbm_d_done = NOW() WHERE dbm_i_id = '$MIGRATION_ID'" > /dev/null; then
			abort "$(ansi red)Unable to mark the migration file $(ansi reset)$MIGRATION_FILE$(ansi red) as done.$(ansi reset)" $DPK_EXIT_DB_TRACKING
		fi
	done
	echo "$(ansi green)Done$(ansi reset)"
}

# _install_config_apache()
# Generation and installation of Apache files.
_install_config_apache() {
	local _CONF_FILE
	if [ -v DPK_OPT["no-apache"] ] || [ "$CONF_INSTALL_APACHE_FILES" = "" ] || [ ! -d /etc/apache2 ]; then
		return
	fi
	echo "$(ansi bold)Installing Apache configuration$(ansi reset)"
	echo "$(ansi dim)> main configuration files$(ansi reset)"
	if [ ! -e /etc/apache2/sites-available/dispak.conf ]; then
		sudo touch /etc/apache2/sites-available/dispak.conf
	fi
	if [ ! -e /etc/apache2/sites-enabled/001-dispak.conf ]; then
		sudo ln -s /etc/apache2/sites-available/dispak.conf /etc/apache2/sites-enabled/001-dispak.conf
	fi
	for _CONF_FILE in $CONF_INSTALL_APACHE_FILES; do
		echo "$(ansi blue)> $_CONF_FILE$(ansi reset)"
		if [ -e "${_CONF_FILE}.gen" ]; then
			echo -n "$(ansi dim)+ Generating... $(ansi reset)"
			if [ ! -x "$_CONF_FILE.gen" ]; then
				chmod +x "$_CONF_FILE.gen"
			fi
			"${_CONF_FILE}.gen" "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}" > "$_CONF_FILE"
			if [ $? -ne 0 ]; then
				echo
				abort "$(ansi red)Apache configuration generation script $(ansi reset)$_CONF_FILE.gen$(ansi red) execution failed.$(ansi reset)"
			fi
		fi
		echo "$(ansi green)done$(ansi reset)"
		if ! grep --quiet "$_CONF_FILE" /etc/apache2/sites-available/dispak.conf ; then
			echo -n "$(ansi dim)+ Adding to Apache configuration... $(ansi reset)"
			sudo bash -c "echo 'Include $_CONF_FILE' >> /etc/apache2/sites-available/dispak.conf"
			echo "$(ansi green)done$(ansi reset)"
		fi
	done
}

# _install_config_files()
# Configure files.
_install_config_files() {
	local LOGIN RIGHTS _FILE
	# chown
	if [ ${#CONF_INSTALL_CHOWN[@]} -ne 0 ]; then
		echo "$(ansi bold)Setting files owner$(ansi reset)"
		for LOGIN in "${!CONF_INSTALL_CHOWN[@]}"; do
			echo "$(ansi dim)> $LOGIN$(ansi reset)"
			sudo chown "$LOGIN" ${CONF_INSTALL_CHOWN["$LOGIN"]}
		done
	fi
	# chgrp
	if [ ${#CONF_INSTALL_CHGRP[@]} -ne 0 ]; then
		echo "$(ansi bold)Setting files group$(ansi reset)"
		for LOGIN in "${!CONF_INSTALL_CHGRP[@]}"; do
			echo "$(ansi dim)> $LOGIN$(ansi reset)"
			sudo chgrp -R "$LOGIN" ${CONF_INSTALL_CHGRP["$LOGIN"]}
		done
	fi
	# chmod
	if [ ${#CONF_INSTALL_CHMOD[@]} -ne 0 ]; then
		echo "$(ansi bold)Setting files access rights$(ansi reset)"
		for RIGHTS in "${!CONF_INSTALL_CHMOD[@]}"; do
			echo "$(ansi dim)> $RIGHTS$(ansi reset)"
			sudo chmod -R "$RIGHTS" ${CONF_INSTALL_CHMOD["$RIGHTS"]}
			for _FILE in ${CONF_INSTALL_CHMOD["$RIGHTS"]}; do
				if [ -d "$_FILE" ]; then
					git checkout -- $(find "$_FILE" -name ".gitignore") > /dev/null
				fi
			done
		done
	fi
	# files generation
	if [ "$CONF_INSTALL_GENERATE" != "" ]; then
		echo "$(ansi bold)Generate files$(ansi reset)"
		for _FILE in $CONF_INSTALL_GENERATE; do
			echo "$(ansi dim)> $_FILE$(ansi reset)"
			if [ ! -e "$_FILE.gen" ]; then
				warn "$(ansi yellow)Generator file $(ansi reset)$_FILE.gen$(ansi yellow) doesn't exist.$(ansi reset)"
				continue
			fi
			if [ ! -x "$_FILE.gen" ]; then
				chmod +x "$_FILE.gen"
			fi
			"${_FILE}.gen" "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}" > "$_FILE"
		done
	fi
}

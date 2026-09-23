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

# Paths of the system configuration files managed by the install rule. Defined as variables
# so that the tests can redirect them to a temporary directory.
DPK_SYSTEMD_DIR="/etc/systemd/system"
DPK_SUPERVISOR_DIR="/etc/supervisor/conf.d"
DPK_XINETD_FILE="/etc/xinetd.d/dispak"

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
	dpk_echo "$(ansi bold)Updating source code repository$(ansi reset)"
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
		dpk_echo "$(ansi bold)Create symlink $(ansi reset)$(ansi dim)$_SYMLINK/${DPK_OPT["tag"]}$(ansi reset)"
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
	dpk_echo "$(ansi bold)Execute pre-install scripts$(ansi reset)"
	for _SCRIPT in $CONF_INSTALL_SCRIPTS_PRE; do
		_SCRIPT="$(echo $_SCRIPT | sed 's/#/ /')"
		_EXEC="$(echo "$_SCRIPT" | cut -d" " -f 1)"
		dpk_echo "> $(ansi dim)$_SCRIPT$(ansi reset)"
		if [ ! -x "$_EXEC" ]; then
			chmod +x "$_EXEC"
		fi
		$_SCRIPT "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}" "$CURRENT_TAG" "$TAG_EVOLUTION"
		if [ $? -ne 0 ]; then
			abort "$(ansi red)Execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_INSTALL_PRE
		fi
	done
	dpk_echo "$(ansi green)Done$(ansi reset)"
}

# _install_post_scripts()
# Execute post-install scripts.
_install_post_scripts() {
	local _SCRIPT _EXEC
	if [ "$CONF_INSTALL_SCRIPTS_POST" = "" ]; then
		return
	fi
	dpk_echo "$(ansi bold)Execute post-install scripts$(ansi reset)"
	for _SCRIPT in $CONF_INSTALL_SCRIPTS_POST; do
		_SCRIPT="$(echo $_SCRIPT | sed 's/#/ /')"
		_EXEC="$(echo "$_SCRIPT" | cut -d" " -f 1)"
		dpk_echo "> $(ansi dim)$_SCRIPT$(ansi reset)"
		if [ ! -x "$_EXEC" ]; then
			chmod +x "$_EXEC"
		fi
		$_SCRIPT "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}" "$CURRENT_TAG" "$TAG_EVOLUTION"
		if [ $? -ne 0 ]; then
			abort "$(ansi red)Execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_INSTALL_POST
		fi
	done
	dpk_echo "$(ansi green)Done$(ansi reset)"
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
		dpk_echo "$(ansi bold)Removing symlink $(ansi reset)$(ansi dim)$_VLINK$(ansi reset)"
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
	dpk_echo "$(ansi bold)Create version alias links$(ansi reset)"
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
		dpk_echo "$(ansi dim)> $_ALIAS_LINK$(ansi reset)"
		ln -sn "$_ALIAS_BASE" "$_ALIAS_LINK"
		if [ $? -ne 0 ]; then
			abort "Unable to create the symlink '$(ansi dim)$_ALIAS_LINK$(ansi reset)'." $DPK_EXIT_ENV
		fi
	done
}

# _install_remove_block()
# Remove the lines between two marker lines (markers included) from the text read on the
# standard input, and write the result on the standard output.
# @param	string	Start marker line.
# @param	string	End marker line.
_install_remove_block() {
	local _LINE _SKIP=0
	while IFS= read -r _LINE || [ -n "$_LINE" ]; do
		if [ "$_LINE" = "$1" ]; then
			_SKIP=1
		fi
		if [ $_SKIP -eq 0 ]; then
			printf '%s\n' "$_LINE"
		fi
		if [ "$_LINE" = "$2" ]; then
			_SKIP=0
		fi
	done
}

# _install_config_marker()
# Write the ownership marker line added at the top of the system configuration files
# installed by Dispak (systemd units, Supervisor files). The marker holds the path of the
# source file in the repository, so the origin of an installed file is easy to find, and
# so the files installed from the current repository can be recognized and cleaned up.
# @param	string	Type of configuration ("SYSTEMD" or "SUPERVISOR").
# @param	string	Path to the source file in the repository (generator script if any).
_install_config_marker() {
	echo "# ┏━━━━━┥DISPAK $1┝━━━┥$2┝━━━━━┓"
}

# _install_copy_config()
# Copy a configuration file to its system destination, preceded by an ownership marker.
# @param	string	Path to the source file.
# @param	string	Path to the destination file.
# @param	string	Ownership marker line.
# @return	0 if the file was written.
_install_copy_config() {
	{ echo "$3"; cat "$1"; } | sudo tee "$2" > /dev/null
}

# _install_generate_config()
# Execute a generator script and write its output to a system configuration file, preceded
# by an ownership marker. The output is generated in a temporary file first, so the
# destination file is left untouched if the generator fails or outputs nothing.
# @param	string	Path to the generator script.
# @param	string	Path to the destination file.
# @param	string	Ownership marker line.
# @return	0 if the file was written, 1 if the generated output was empty (nothing written),
#		2 if the generator failed.
_install_generate_config() {
	local _TMP_FILE
	chmod +x "$1"
	_TMP_FILE="$(mktemp --tmpdir=/tmp dispak-config.XXXXXXXXXX)"
	if ! sudo bash -c "\"$1\" \"${DPK_OPT["platform"]}\" \"${DPK_OPT["tag"]}\" > \"$_TMP_FILE\""; then
		rm -f "$_TMP_FILE"
		return 2
	fi
	if [ ! -s "$_TMP_FILE" ]; then
		rm -f "$_TMP_FILE"
		return 1
	fi
	_install_copy_config "$_TMP_FILE" "$2" "$3"
	rm -f "$_TMP_FILE"
}

# _install_find_orphan_configs()
# List the system configuration files which were installed by Dispak from the current
# repository (recognized by their ownership marker), but not during the current execution:
# their source file was removed from the repository, or its generator outputs nothing now.
# @param	string	Type of configuration ("SYSTEMD" or "SUPERVISOR").
# @param	string	Path to the source directory in the repository.
# @param	string	Space-separated list of the files installed during the current execution.
# @param	string...	System files to inspect (usually given as glob patterns).
_install_find_orphan_configs() {
	local _TYPE="$1" _SOURCE_DIR="$2" _INSTALLED="$3" _MARK_PREFIX _FILE
	shift 3
	# marker line without its ending, to match any source file of the directory
	_MARK_PREFIX="$(_install_config_marker "$_TYPE" "$_SOURCE_DIR/")"
	_MARK_PREFIX="${_MARK_PREFIX%┝━━━━━┓}"
	for _FILE in $(sudo grep -lF -- "$_MARK_PREFIX" "$@" 2> /dev/null); do
		if [ ! -f "$_FILE" ]; then
			continue
		fi
		if [[ " $_INSTALLED " != *" $_FILE "* ]]; then
			echo "$_FILE"
		fi
	done
}

# _install_crontab()
# Install new crontab file. If the repository has no crontab file anymore, the block
# installed by a previous deployment is removed from the crontab.
_install_crontab() {
	local START_MARK END_MARK BEGIN_GEN END_GEN
	if [ -v DPK_OPT["no-crontab"] ]; then
		return
	fi
	START_MARK="# ┏━━━━━┥DISPAK CRONTAB START┝━━━┥$GIT_REPO_PATH/etc/crontab┝━━━━━┓"
	END_MARK="# ┗━━━━━┥DISPAK CRONTAB END┝━━━━━┥$GIT_REPO_PATH/etc/crontab┝━━━━━┛"
	if [ ! -f "$GIT_REPO_PATH/etc/crontab" ] && [ ! -f "$GIT_REPO_PATH/etc/crontab.gen" ]; then
		if ! crontab -l 2> /dev/null | grep -qxF -- "$START_MARK"; then
			return
		fi
		dpk_echo "$(ansi bold)Removing crontab configuration$(ansi reset)"
		crontab -l 2> /dev/null | _install_remove_block "$START_MARK" "$END_MARK" | crontab -
		dpk_echo "$(ansi green)Done$(ansi reset)"
		return
	fi
	dpk_echo "$(ansi bold)Installing crontab$(ansi reset)"
	if [ -e "$GIT_REPO_PATH/etc/crontab.gen" ]; then
		dpk_echo -n "$(ansi dim)+ Generating... $(ansi reset)"
		chmod +x "$GIT_REPO_PATH/etc/crontab.gen"
		"$GIT_REPO_PATH/etc/crontab.gen" "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}" > "$GIT_REPO_PATH/etc/crontab"
		if [ $? -ne 0 ]; then
			dpk_echo
			abort "$(ansi red)Crontab configuration generation script $(ansi reset)$GIT_REPO_PATH/etc/crontab.gen$(ansi red) execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_GENERATOR
		fi
		dpk_echo "$(ansi green)done$(ansi reset)"
	fi
	if ! crontab -l 2> /dev/null | grep -qxF -- "$START_MARK"; then
		(crontab -l 2>/dev/null; echo; echo $START_MARK; echo; cat "$GIT_REPO_PATH/etc/crontab"; echo $END_MARK) | crontab -
	else
		BEGIN_GEN=$(crontab -l 2>/dev/null | grep -nxF -- "$START_MARK" | cut -d: -f 1)
		END_GEN=$(crontab -l 2>/dev/null | grep -nxF -- "$END_MARK" | cut -d: -f 1)
		(crontab -l 2>/dev/null | head -n $BEGIN_GEN; echo; cat "$GIT_REPO_PATH/etc/crontab"; crontab -l 2>/dev/null | tail -n +$END_GEN) | crontab -
	fi
	dpk_echo "$(ansi green)Done$(ansi reset)"
}

# _install_xinetd_reload()
# Ask xinetd to reload its configuration.
_install_xinetd_reload() {
	dpk_echo -n "$(ansi dim)+ Reloading xinetd$(ansi reset) "
	if ! sudo systemctl reload xinetd; then
		dpk_echo
		warn "Unable to reload xinetd."
		return
	fi
	dpk_echo "$(ansi green)done$(ansi reset)"
}

# _install_xinetd()
# Install new xinetd file. If the repository has no xinetd file anymore, the block
# installed by a previous deployment is removed from the system file.
_install_xinetd() {
	local START_MARK END_MARK BEGIN_GEN END_GEN XINETD_TMP_FILE
	if [ -v DPK_OPT["no-xinetd"] ]; then
		return
	fi
	START_MARK="# ┏━━━━━┥DISPAK XINETD START┝━━━┥$GIT_REPO_PATH/etc/xinetd┝━━━━━┓"
	END_MARK="# ┗━━━━━┥DISPAK XINETD END┝━━━━━┥$GIT_REPO_PATH/etc/xinetd┝━━━━━┛"
	if [ ! -f "$GIT_REPO_PATH/etc/xinetd" ] && [ ! -f "$GIT_REPO_PATH/etc/xinetd.gen" ]; then
		if [ ! -e "$DPK_XINETD_FILE" ] || ! sudo grep -qxF -- "$START_MARK" "$DPK_XINETD_FILE"; then
			return
		fi
		dpk_echo "$(ansi bold)Removing xinetd configuration$(ansi reset)"
		XINETD_TMP_FILE="$(mktemp --tmpdir=/tmp dispak-xinetd.XXXXXXXXXX)"
		sudo cat "$DPK_XINETD_FILE" | _install_remove_block "$START_MARK" "$END_MARK" > "$XINETD_TMP_FILE"
		sudo tee "$DPK_XINETD_FILE" < "$XINETD_TMP_FILE" > /dev/null
		rm -f "$XINETD_TMP_FILE"
		_install_xinetd_reload
		dpk_echo "$(ansi green)Done$(ansi reset)"
		return
	fi
	dpk_echo "$(ansi bold)Installing xinetd configuration$(ansi reset)"
	if [ ! -e "$DPK_XINETD_FILE" ]; then
		sudo touch "$DPK_XINETD_FILE"
		sudo chmod 644 "$DPK_XINETD_FILE"
	fi
	if [ -e "$GIT_REPO_PATH/etc/xinetd.gen" ]; then
		dpk_echo -n "$(ansi dim)+ Generating... $(ansi reset)"
		chmod +x "$GIT_REPO_PATH/etc/xinetd.gen"
		"$GIT_REPO_PATH/etc/xinetd.gen" "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}" > "$GIT_REPO_PATH/etc/xinetd"
		if [ $? -ne 0 ]; then
			dpk_echo
			abort "$(ansi red)Xinetd configuration generation script $(ansi reset)$GIT_REPO_PATH/etc/xinetd.gen$(ansi red) execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_GENERATOR
		fi
		dpk_echo "$(ansi green)done$(ansi reset)"
	fi
	sudo cat "$DPK_XINETD_FILE" | grep -qxF -- "$START_MARK"
	if [ $? -ne 0 ]; then
		sudo bash -c "(echo; echo \"$START_MARK\"; cat \"$GIT_REPO_PATH/etc/xinetd\"; echo \"$END_MARK\") >> \"$DPK_XINETD_FILE\""
	else
		BEGIN_GEN=$(sudo cat "$DPK_XINETD_FILE" | grep -nxF -- "$START_MARK" | cut -d: -f 1)
		END_GEN=$(sudo cat "$DPK_XINETD_FILE" | grep -nxF -- "$END_MARK" | cut -d: -f 1)
		XINETD_TMP_FILE="$(mktemp --tmpdir=/tmp dispak-xinetd.XXXXXXXXXX)"
		sudo cat "$DPK_XINETD_FILE" | head -n $BEGIN_GEN > "$XINETD_TMP_FILE"
		cat "$GIT_REPO_PATH/etc/xinetd" >> "$XINETD_TMP_FILE"
		sudo cat "$DPK_XINETD_FILE" | tail -n +$END_GEN >> "$XINETD_TMP_FILE"
		sudo tee "$DPK_XINETD_FILE" < "$XINETD_TMP_FILE" > /dev/null
		rm -f "$XINETD_TMP_FILE"
	fi
	_install_xinetd_reload
	dpk_echo "$(ansi green)Done$(ansi reset)"
}

# _install_supervisor()
# Install new Supervisor files, and remove the files installed by previous deployments
# which are not part of the repository anymore.
_install_supervisor() {
	local FILENAME DEST MARK INSTALLED ORPHANS CHANGED
	if [ -v DPK_OPT["no-supervisor"] ]; then
		return
	fi
	INSTALLED=""
	CHANGED=0
	if [ -d "$GIT_REPO_PATH/etc/supervisor" ]; then
		dpk_echo "$(ansi bold)Installing Supervisor configuration$(ansi reset)"
		if [ ! -d "$DPK_SUPERVISOR_DIR" ]; then
			dpk_echo
			abort "$(ansi red)Unable to find directory $(ansi reset)$DPK_SUPERVISOR_DIR" $DPK_EXIT_ENV
		fi
		for FILENAME in "$GIT_REPO_PATH"/etc/supervisor/*; do
			if [[ "$FILENAME" != *.conf ]] && [[ "$FILENAME" != *.conf.gen ]]; then
				continue
			fi
			DEST="$DPK_SUPERVISOR_DIR/$(basename "${FILENAME%.gen}")"
			MARK="$(_install_config_marker SUPERVISOR "$FILENAME")"
			if [[ "$FILENAME" == *.gen ]]; then
				dpk_echo -n "$(ansi dim)+ Generating$(ansi reset) $DEST "
				_install_generate_config "$FILENAME" "$DEST" "$MARK"
				case $? in
					1)
						dpk_echo "$(ansi yellow)empty$(ansi reset)"
						continue
						;;
					2)
						dpk_echo
						abort "$(ansi red)Supervisor configuration generation script $(ansi reset)$FILENAME$(ansi red) execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_GENERATOR
						;;
				esac
			else
				dpk_echo -n "$(ansi dim)+ Copying$(ansi reset) $DEST "
				if ! _install_copy_config "$FILENAME" "$DEST" "$MARK"; then
					dpk_echo
					abort "$(ansi red)Unable to copy file $(ansi reset)$FILENAME$(ansi red) to $(ansi reset)$DEST$(ansi red).$(ansi reset)" $DPK_EXIT_ENV
				fi
			fi
			dpk_echo "$(ansi green)done$(ansi reset)"
			INSTALLED="$INSTALLED $DEST"
			CHANGED=1
		done
	fi
	# remove the files installed by previous deployments and not installed this time
	ORPHANS="$(_install_find_orphan_configs SUPERVISOR "$GIT_REPO_PATH/etc/supervisor" "$INSTALLED" "$DPK_SUPERVISOR_DIR"/*.conf)"
	if [ "$ORPHANS" != "" ]; then
		dpk_echo "$(ansi bold)Removing obsolete Supervisor configuration$(ansi reset)"
		for FILENAME in $ORPHANS; do
			dpk_echo "$(ansi dim)+ Removing$(ansi reset) $FILENAME"
			sudo rm -f "$FILENAME"
		done
		CHANGED=1
	fi
	if [ $CHANGED -eq 1 ]; then
		dpk_echo "$(ansi dim)+ Restarting Supervisor$(ansi reset)"
		if ! sudo supervisorctl reread || ! sudo supervisorctl update; then
			abort "$(ansi red)Unable to restart Supervisor.$(ansi reset)" $DPK_EXIT_ENV
		fi
		dpk_echo "$(ansi green)Done$(ansi reset)"
	fi
}

# _install_systemd_unit()
# Install a systemd unit file: copied to the system directory, or generated if the source
# file is a generator script.
# @param	string	Path to the source file in the repository.
# @param	string	Path to the destination unit file.
# @return	0 if the unit file was installed, 1 if the generated output was empty (nothing installed).
_install_systemd_unit() {
	local _MARK
	_MARK="$(_install_config_marker SYSTEMD "$1")"
	if [[ "$1" == *.gen ]]; then
		dpk_echo -n "$(ansi dim)+ Generating$(ansi reset) $2 "
		_install_generate_config "$1" "$2" "$_MARK"
		case $? in
			1)
				dpk_echo "$(ansi yellow)empty$(ansi reset)"
				return 1
				;;
			2)
				dpk_echo
				abort "$(ansi red)Systemd configuration generation script $(ansi reset)$1$(ansi red) execution failed.$(ansi reset)" $DPK_EXIT_SCRIPT_GENERATOR
				;;
		esac
	else
		dpk_echo -n "$(ansi dim)+ Copying$(ansi reset) $2 "
		if ! _install_copy_config "$1" "$2" "$_MARK"; then
			dpk_echo
			abort "$(ansi red)Unable to copy file$(ansi reset) $1 $(ansi red)to$(ansi reset) $2" $DPK_EXIT_ENV
		fi
	fi
	dpk_echo "$(ansi green)done$(ansi reset)"
}

# _install_systemd_start()
# Reload the systemd configuration, then enable and (re)start the given unit.
# @param	string	Name of the unit (e.g. "myservice.service" or "mytarget.target").
_install_systemd_start() {
	dpk_echo -n "$(ansi dim)+ Starting$(ansi reset) $1 "
	if ! sudo systemctl daemon-reload; then
		dpk_echo
		dpk_echo "$(ansi red)Systemd is unable to reload the daemon configuration files.$(ansi reset)"
	elif ! sudo systemctl enable "$1"; then
		dpk_echo
		dpk_echo "$(ansi red)Unable to enable unit$(ansi reset) $1$(ansi red).$(ansi reset)"
	elif ! sudo systemctl restart "$1"; then
		dpk_echo
		dpk_echo "$(ansi red)Unable to start unit$(ansi reset) $1$(ansi red).$(ansi reset)"
	else
		dpk_echo "$(ansi green)done$(ansi reset)"
	fi
}

# _install_systemd()
# Install new systemd files, and remove the units installed by previous deployments
# which are not part of the repository anymore (or which generator outputs nothing now).
_install_systemd() {
	local FILENAME UNIT_NAME TEMPLATE_NAME SOURCE_FILE INSTALLED ORPHANS UNIT_FILE
	if [ -v DPK_OPT["no-systemd"] ]; then
		return
	fi
	INSTALLED=""
	if [ -d "$GIT_REPO_PATH/etc/systemd" ]; then
		dpk_echo "$(ansi bold)Installing systemd configuration$(ansi reset)"
		if [ ! -d "$DPK_SYSTEMD_DIR" ]; then
			dpk_echo
			abort "$(ansi red)Unable to find directory $(ansi reset)$DPK_SYSTEMD_DIR" $DPK_EXIT_ENV
		fi
		for FILENAME in "$GIT_REPO_PATH"/etc/systemd/*; do
			if [[ "$FILENAME" == *@.service ]] || [[ "$FILENAME" == *@.service.gen ]]; then
				# template units are installed with their target
				continue
			elif [[ "$FILENAME" == *.target ]] || [[ "$FILENAME" == *.target.gen ]]; then
				# target, with its associated "@.service" template unit
				UNIT_NAME="$(basename "${FILENAME%.gen}")"
				TEMPLATE_NAME="${UNIT_NAME%.target}@.service"
				SOURCE_FILE="$GIT_REPO_PATH/etc/systemd/$TEMPLATE_NAME"
				if [ -f "$SOURCE_FILE.gen" ]; then
					SOURCE_FILE="$SOURCE_FILE.gen"
				elif [ ! -f "$SOURCE_FILE" ]; then
					abort "$(ansi red)Unable to find file$(ansi reset) $SOURCE_FILE" $DPK_EXIT_ENV
				fi
				if ! _install_systemd_unit "$FILENAME" "$DPK_SYSTEMD_DIR/$UNIT_NAME"; then
					continue
				fi
				if ! _install_systemd_unit "$SOURCE_FILE" "$DPK_SYSTEMD_DIR/$TEMPLATE_NAME"; then
					# no template unit, no target
					sudo rm -f "$DPK_SYSTEMD_DIR/$UNIT_NAME"
					continue
				fi
				INSTALLED="$INSTALLED $DPK_SYSTEMD_DIR/$UNIT_NAME $DPK_SYSTEMD_DIR/$TEMPLATE_NAME"
			elif [[ "$FILENAME" == *.service ]] || [[ "$FILENAME" == *.service.gen ]]; then
				# simple service
				UNIT_NAME="$(basename "${FILENAME%.gen}")"
				if ! _install_systemd_unit "$FILENAME" "$DPK_SYSTEMD_DIR/$UNIT_NAME"; then
					continue
				fi
				INSTALLED="$INSTALLED $DPK_SYSTEMD_DIR/$UNIT_NAME"
			else
				continue
			fi
			_install_systemd_start "$UNIT_NAME"
		done
	fi
	# remove the units installed by previous deployments and not installed this time
	# (targets first: their template units' instances are stopped with them)
	ORPHANS="$(_install_find_orphan_configs SYSTEMD "$GIT_REPO_PATH/etc/systemd" "$INSTALLED" "$DPK_SYSTEMD_DIR"/*.target "$DPK_SYSTEMD_DIR"/*.service)"
	if [ "$ORPHANS" = "" ]; then
		return
	fi
	dpk_echo "$(ansi bold)Removing obsolete systemd configuration$(ansi reset)"
	for UNIT_FILE in $ORPHANS; do
		UNIT_NAME="$(basename "$UNIT_FILE")"
		dpk_echo -n "$(ansi dim)+ Removing$(ansi reset) $UNIT_FILE "
		# a template unit can't be stopped by itself (its instances are stopped with their target)
		if [[ "$UNIT_NAME" != *@.service ]]; then
			if ! sudo systemctl stop "$UNIT_NAME"; then
				dpk_echo
				warn "Unable to stop unit $UNIT_NAME."
			elif ! sudo systemctl disable "$UNIT_NAME"; then
				dpk_echo
				warn "Unable to disable unit $UNIT_NAME."
			fi
		fi
		sudo rm -f "$UNIT_FILE"
		dpk_echo "$(ansi green)done$(ansi reset)"
	done
	if ! sudo systemctl daemon-reload; then
		dpk_echo "$(ansi red)Systemd is unable to reload the daemon configuration files.$(ansi reset)"
	fi
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
	dpk_echo "$(ansi bold)Database migration$(ansi reset)"
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
		dpk_echo "$(ansi dim)Executing database migration file $(ansi blue)$MIGRATION_FILE$(ansi reset)"
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
			dpk_echo "$OUTPUT"
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
	dpk_echo "$(ansi green)Done$(ansi reset)"
}

# _install_config_apache()
# Generation and installation of Apache files.
_install_config_apache() {
	local _CONF_FILE
	if [ -v DPK_OPT["no-apache"] ] || [ "$CONF_INSTALL_APACHE_FILES" = "" ] || [ ! -d /etc/apache2 ]; then
		return
	fi
	dpk_echo "$(ansi bold)Installing Apache configuration$(ansi reset)"
	dpk_echo "$(ansi dim)> main configuration files$(ansi reset)"
	if [ ! -e /etc/apache2/sites-available/dispak.conf ]; then
		sudo touch /etc/apache2/sites-available/dispak.conf
	fi
	if [ ! -e /etc/apache2/sites-enabled/001-dispak.conf ]; then
		sudo ln -s /etc/apache2/sites-available/dispak.conf /etc/apache2/sites-enabled/001-dispak.conf
	fi
	for _CONF_FILE in $CONF_INSTALL_APACHE_FILES; do
		dpk_echo "$(ansi blue)> $_CONF_FILE$(ansi reset)"
		if [ -e "${_CONF_FILE}.gen" ]; then
			dpk_echo -n "$(ansi dim)+ Generating... $(ansi reset)"
			if [ ! -x "$_CONF_FILE.gen" ]; then
				chmod +x "$_CONF_FILE.gen"
			fi
			"${_CONF_FILE}.gen" "${DPK_OPT["platform"]}" "${DPK_OPT["tag"]}" > "$_CONF_FILE"
			if [ $? -ne 0 ]; then
				dpk_echo
				abort "$(ansi red)Apache configuration generation script $(ansi reset)$_CONF_FILE.gen$(ansi red) execution failed.$(ansi reset)"
			fi
		fi
		dpk_echo "$(ansi green)done$(ansi reset)"
		if ! grep --quiet "$_CONF_FILE" /etc/apache2/sites-available/dispak.conf ; then
			dpk_echo -n "$(ansi dim)+ Adding to Apache configuration... $(ansi reset)"
			sudo bash -c "echo 'Include $_CONF_FILE' >> /etc/apache2/sites-available/dispak.conf"
			dpk_echo "$(ansi green)done$(ansi reset)"
		fi
	done
}

# _install_config_files()
# Configure files.
_install_config_files() {
	local LOGIN RIGHTS _FILE
	# chown
	if [ ${#CONF_INSTALL_CHOWN[@]} -ne 0 ]; then
		dpk_echo "$(ansi bold)Setting files owner$(ansi reset)"
		for LOGIN in "${!CONF_INSTALL_CHOWN[@]}"; do
			dpk_echo "$(ansi dim)> $LOGIN$(ansi reset)"
			sudo chown "$LOGIN" ${CONF_INSTALL_CHOWN["$LOGIN"]}
		done
	fi
	# chgrp
	if [ ${#CONF_INSTALL_CHGRP[@]} -ne 0 ]; then
		dpk_echo "$(ansi bold)Setting files group$(ansi reset)"
		for LOGIN in "${!CONF_INSTALL_CHGRP[@]}"; do
			dpk_echo "$(ansi dim)> $LOGIN$(ansi reset)"
			sudo chgrp -R "$LOGIN" ${CONF_INSTALL_CHGRP["$LOGIN"]}
		done
	fi
	# chmod
	if [ ${#CONF_INSTALL_CHMOD[@]} -ne 0 ]; then
		dpk_echo "$(ansi bold)Setting files access rights$(ansi reset)"
		for RIGHTS in "${!CONF_INSTALL_CHMOD[@]}"; do
			dpk_echo "$(ansi dim)> $RIGHTS$(ansi reset)"
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
		dpk_echo "$(ansi bold)Generate files$(ansi reset)"
		for _FILE in $CONF_INSTALL_GENERATE; do
			dpk_echo "$(ansi dim)> $_FILE$(ansi reset)"
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

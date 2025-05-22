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
RULE_OPTIONAL_PARAMS="platform tag no-apache no-crontab no-xinetd no-db-migration"

# Definition of configuration associative arrays.
declare -A CONF_INSTALL_SYMLINK
declare -A CONF_INSTALL_CHOWN
declare -A CONF_INSTALL_CHMOD

# Show help for this rule.
rule_help_install() {
	echo "   dpk $(ansi bold)install$(ansi reset) $(ansi dim)[--$(ansi reset)platform$(ansi dim)=dev|test|prod] [$(ansi reset)--tag$(ansi dim)=$CONF_GIT_MAIN|X.Y.Z] [$(ansi reset)--no-apache$(ansi dim)] [$(ansi reset)--no-crontab$(ansi dim)] [$(ansi reset)--no-xinetd$(ansi dim)] [$(ansi reset)--no-db-migration$(ansi dim)]$(ansi reset)"
	echo "       $(ansi dim)Deploy source code (pull tag from GitHub, generate files, set files rights).$(ansi reset)"
	echo "       --platform        $(ansi dim)Definition of the current platform. Otherwise, Dispak will try to detect it.$(ansi reset)"
	echo "       --tag             $(ansi dim)Tag to install (or $(ansi reset)$CONF_GIT_MAIN$(ansi dim) to use its last revision). Otherwise, the last tagged version will be installed.$(ansi reset)"
	echo "       --no-apache       $(ansi dim)Don't install Apache configuration files, even if Apache is installed on the current machine.$(ansi reset)"
	echo "       --no-crontab      $(ansi dim)Don't install crontab configuration.$(ansi reset)"
	echo "       --no-xinetd       $(ansi dim)Don't install xinetd configuration.$(ansi reset)"
	echo "       --no-db-migration $(ansi dim)Don't perform database migration.$(ansi reset)"
	echo "       $(ansi yellow)⚠ Needs sudo rights$(ansi reset)"
}

# Execution of the rule
rule_exec_install() {
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
			abort "$(ansi red)It's forbidden to install $(ansi reset)unstable$(ansi red) tags on production server.$(ansi reset)"
		fi
	fi
	# get the tag's configuration file
	if [ -f "$GIT_REPO_PATH/etc/dispak.conf" ]; then
		git checkout "${DPK_OPT["tag"]}" -- "$GIT_REPO_PATH/etc/dispak.conf"
		if [ $? -ne 0 ]; then
			abort "$(ansi red)Unable to checkout file $(ansi reset)etc/dispak.conf$(ansi red) from tag $(ansi reset)${DPK_OPT["tag"]}"
		fi
		# read the tag's configuration file
		. "$(eval realpath "$GIT_REPO_PATH/etc/dispak.conf")"
		# reset the configuration file
		git restore --staged --worktree "$GIT_REPO_PATH/etc/dispak.conf"
	fi
	# remove symlinks from the currently installed tag
	CURRENT_TAG="$(git symbolic-ref -q --short HEAD || git describe --tags --exact-match)"
	if [ "$CURRENT_TAG" != "$CONF_GIT_MAIN" ] && [ ${#CONF_INSTALL_SYMLINK[@]} -ne 0 ]; then
		for _SYMLINK in ${!CONF_INSTALL_SYMLINK[@]}; do
			if [ -L "$_SYMLINK/$CURRENT_TAG" ]; then
				echo "$(ansi bold)Removing symlink $(ansi reset)$(ansi dim)$_SYMLINK/$CURRENT_TAG$(ansi reset)"
				rm -f "$_SYMLINK/$CURRENT_TAG"
			fi
		done
	fi
	# execute pre-install scripts
	_install_pre_scripts
	# execute pre-config scripts
	_config_pre_scripts
	# deploy source code
	git_fetch
	echo "$(ansi bold)Updating source code repository$(ansi reset)"
	if [ "${DPK_OPT["tag"]}" = "$CONF_GIT_MAIN" ]; then
		if ! git checkout "$CONF_GIT_MAIN" --quiet ; then
			abort "$(ansi red)Failed to move back to '$CONF_GIT_MAIN' branch.$(ansi reset)"
		fi
	else
		if ! git checkout "tags/${DPK_OPT["tag"]}" --quiet ; then
			abort "$(ansi red)Failed to update repository to tag '${DPK_OPT["tag"]}'.$(ansi reset)"
		fi
		# create symlinks
		for _SYMLINK in ${!CONF_INSTALL_SYMLINK[@]}; do
			echo "$(ansi bold)Create symlink $(ansi reset)$(ansi dim)${CONF_INSTALL_SYMLINK["$_SYMLINK"]}/${DPK_OPT["tag"]}$(ansi reset)"
			ln -s "${CONF_INSTALL_SYMLINK["$_SYMLINK"]}" "$_SYMLINK/${DPK_OPT["tag"]}"
		done
	fi
	# install crontab
	_install_crontab
	# database migration
	_install_db_migration
	# Apache configuration
	_install_config_apache
	# xinetd configuration
	_install_xinetd
	# files configuration
	_install_config_files
	# execute post-config scripts
	_config_post_scripts
	# execute post-install scripts
	_install_post_scripts
}

# _install_pre_scripts()
# Execute pre-install scripts.
_install_pre_scripts() {
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
			abort "$(ansi red)Execution failed.$(ansi reset)"
		fi
	done
	echo "$(ansi gree)Done$(ansi reset)"
}

# _install_post_scripts()
# Execute post-install scripts.
_install_post_scripts() {
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
			abort "$(ansi red)Execution failed.$(ansi reset)"
		fi
	done
	echo "$(ansi gree)Done$(ansi reset)"
}

# _install_crontab()
# Install new crontab file.
_install_crontab() {
	if [ "${DPK_OPT["no-crontab"]}" != "" ]; then
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
			abort "$(ansi red)Crontab configuration generation script $(ansi reset)$GIT_REPO_PATH/etc/crontab.gen$(ansi red) execution failed.$(ansi reset)"
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
	if [ "${DPK_OPT["no-xinetd"]}" != "" ]; then
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
			abort "$(ansi red)Xinetd configuration generation script $(ansi reset)$GIT_REPO_PATH/etc/xinetd.gen$(ansi red) execution failed.$(ansi reset)"
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

# _install_db_migration()
# Do the migration of a new version of the database.
_install_db_migration() {
	if [ "${DPK_OPT["no-db-migration"]}" != "" ] || [ "$CONF_DB_HOST" = "" ] || [ "$CONF_DB_PORT" = "" ] || [ "$CONF_DB_USER" = "" ] || [ "$CONF_DB_PWD" = "" ] || [ "$CONF_DB_MIGRATION_BASE" = "" ] || [ "$CONF_DB_MIGRATION_TABLE" = "" ]; then
		return
	fi
	echo "$(ansi bold)Database migration$(ansi reset)"
	# loop on migration files
	for MIGRATION in $(ls "$GIT_REPO_PATH/etc/database/migrations" | grep -v current | sort -V); do
		NBR=$(echo "SELECT COUNT(*) AS n FROM $CONF_DB_MIGRATION_BASE.$CONF_DB_MIGRATION_TABLE WHERE dbm_s_version = '$MIGRATION' AND dbm_d_done IS NOT NULL" | MYSQL_PWD="$CONF_DB_PWD" mysql -u "$CONF_DB_USER" -h "$CONF_DB_HOST" -P "$CONF_DB_PORT" | tail -1)
		if [ "$NBR" != "0" ]; then
			continue
		fi
		echo "$(ansi dim)Executing database migration file $(ansi blue)$GIT_REPO_PATH/etc/database/migrations/$MIGRATION$(ansi reset)"
		MIGRATION_ID=$(echo "INSERT INTO $CONF_DB_MIGRATION_BASE.$CONF_DB_MIGRATION_TABLE SET dbm_d_creation = NOW(), dbm_s_version = '$MIGRATION'; SELECT LAST_INSERT_ID()" | MYSQL_PWD="$CONF_DB_PWD" mysql -u "$CONF_DB_USER" -h "$CONF_DB_HOST" -P "$CONF_DB_PORT" | tail -1)
		MYSQL_PWD="$CONF_DB_PWD" mysql -u "$CONF_DB_USER" -h "$CONF_DB_HOST" -P "$CONF_DB_PORT" < "$GIT_REPO_PATH/etc/database/migrations/$MIGRATION"
		echo "UPDATE $CONF_DB_MIGRATION_BASE.$CONF_DB_MIGRATION_TABLE SET dbm_d_done = NOW() WHERE dbm_i_id = '$MIGRATION_ID'" | MYSQL_PWD="$CONF_DB_PWD" mysql -u "$CONF_DB_USER" -h "$CONF_DB_HOST" -P "$CONF_DB_PORT"
	done
	echo "$(ansi green)Done$(ansi reset)"
}

# _install_config_apache()
# Generation and installation of Apache files.
_install_config_apache() {
	if [ "${DPK_OPT["no-apache"]}" != "" ] || [ "$CONF_INSTALL_APACHE_FILES" = "" ] || [ ! -d /etc/apache2 ]; then
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
			sudo chgrp "$LOGIN" ${CONF_INSTALL_CHGRP["$LOGIN"]}
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

#!/bin/bash

# "install" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="install"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="platform tag"

# Show help for this rule.
rule_help_install() {
	echo "  dpk $(ansi bold)install$(ansi reset) $(ansi dim)[--platform=dev|test|prod]$(ansi reset) $(ansi dim)[--tag=master|X.Y.Z]$(ansi reset)"
	echo "      $(ansi dim)Deploy source code on a specified platform (pull tag from GitHub, generate files, set files rights).$(ansi reset)"
	echo "      $(ansi dim)Detect the current platform if the $(ansi reset)platform$(ansi dim) option is not set.$(ansi reset)"
	echo "      $(ansi dim)Install the last tagged version unless the $(ansi reset)tag$(ansi dim) option is used.$(ansi reset)"
	echo "      $(ansi yellow)⚠ Needs sudo rights$(ansi reset)"
}

# Execution of the rule
rule_exec_install() {
	check_git
	check_sudo
	check_tag
	check_platform
	# check that only stable tag is installed on production servers
	if [ "${DPK_OPTIONS["platform"]}" = "prod" ]; then
		TAG_MINOR=$(echo "${DPK_OPTIONS["tag"]}" | cut -d"." -f2)
		if [ "$(($TAG_MINOR % 2))" != "0" ]; then
			abort "$(ansi red)It's forbidden to install $(ansi reset)unstable$(ansi red) tags on production server.$(ansi reset)"
		fi
	fi
	# remove symlink from the currently installed tag
	if [ "$CONF_SYMLINK_DIR" != "" ] && [ "$CONF_SYMLINK_TARGET" != "" ]; then
		CURRENT_TAG="$(git symbolic-ref -q --short HEAD || git describe --tags --exact-match)"
		if [ "$CURRENT_TAG" != "master" ] && [ -L "$CONF_SYMLINK_DIR/$CURRENT_TAG" ]; then
			echo "$(ansi bold)Removing symlink$(ansi reset) $(ansi dim)$CONF_SYMLINK_DIR/$CURRENT_TAG$(ansi reset)"
			rm -f "$CONF_SYMLINK_DIR/$CURRENT_TAG"
		fi
	fi
	# execute pre-install scripts
	_install_pre_scripts
	# deploy source code
	echo "$(ansi bold)Fetching new tags and branches$(ansi reset)"
	git fetch --all --tags --prune --quiet
	echo "$(ansi bold)Updating source code repository$(ansi reset)"
	if [ "${DPK_OPTIONS["tag"]}" = "master" ]; then
		if ! git checkout master --quiet ; then
			abort "$(ansi red)Failed to move back to master branch.$(ansi reset)"
		fi
	else
		if ! git checkout "tags/${DPK_OPTIONS["tag"]}" --quiet ; then
			abort "$(ansi red)Failed to update repository to tag '${DPK_OPTIONS["tag"]}'.$(ansi reset)"
		fi
		# create symlinks
		for _SYMLINK in ${!CONF_INSTALL_SYMLINK[@]}; do
			echo "$(ansi bold)Create symlink $(ansi reset)$(ansi dim)${CONF_INSTALL_SYMLINK["$_SYMLINK"]}/${DPK_OPTIONS["tag"]}$(ansi reset)"
			ln -s "$_SYMLINK" "${CONF_INSTALL_SYMLINK["$_SYMLINK"]}/${DPK_OPTIONS["tag"]}"
		done
	fi
	# install crontab
	_install_crontab
	# database migration
	_install_db_migration
	# Apache configuration
	_install_config_apache
	# files configuration
	_install_config_files
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

# _install_post_scripts()
# Execute post-install scripts.
_install_post_scripts() {
	if [ "$CONF_INSTALL_SCRIPTS_POST" = "" ]; then
		return
	fi
	echo "$(ansi bold)Execute post-install scripts$(ansi reset)"
	for _SCRIPT in $CONF_INSTALL_SCRIPTS_POST; do
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

# _install_crontab()
# Install new crontab file.
_install_crontab() {
	if [ ! -f "$GIT_REPO_PATH/etc/crontab" ]; then
		return
	fi
	echo "$(ansi bold)Installing crontab$(ansi reset)"
	echo "$(crontab -l 2>/dev/null)" | grep "^### DISPAK CRONTAB START ###$$" > /dev/null
	if [ $? -ne 0 ]; then
		(crontab -l 2>/dev/null; echo; echo "### DISPAK CRONTAB START ###"; echo; cat "$GIT_REPO_PATH/etc/crontab"; echo "### DISPAK CRONTAB END ###") | crontab -
	else
		BEGIN_GEN=$(crontab -l 2>/dev/null | grep -n '### DISPAK CRONTAB START ###' | sed 's/\(.*\):.*/\1/g')
		END_GEN=$(crontab -l 2>/dev/null | grep -n '### DISPAK CRONTAB END ###' | sed 's/\(.*\):.*/\1/g')
		(crontab -l 2>/dev/null | head -n $BEGIN_GEN; echo; cat "$GIT_REPO_PATH/etc/crontab"; crontab -l 2>/dev/null | tail -n +$END_GEN) | crontab -
	fi
	echo "$(ansi green)Done$(ansi reset)"
}

# _install_db_migration()
# Do the migration of a new version of the database.
_install_db_migration() {
	if [ "$CONF_DB_HOST" = "" ] || [ "$CONF_DB_USER" = "" ] || [ "$CONF_DB_PWD" = "" ] || [ "$CONF_DB_MIGRATION_BASE" = "" ] || [ "$CONF_DB_MIGRATION_TABLE" = "" ]; then
		return
	fi
	echo "$(ansi bold)Database migration$(ansi reset)"
	for MIGRATION in $(ls "$GIT_REPO_PATH/etc/database/migrations" | grep -v current | sort -V); do
		NBR=$(echo "SELECT COUNT(*) AS n FROM $CONF_DB_MIGRATION_BASE.$CONF_DB_MIGRATION_TABLE WHERE dbm_s_version = '$MIGRATION' AND dbm_d_done IS NOT NULL" | MYSQL_PWD="$CONF_DB_PWD" mysql -u $CONF_DB_USER -h $CONF_DB_HOST | tail -1)
		if [ "$NBR" != "0" ]; then
			continue
		fi
		echo "$(ansi dim)Executing database migration file $(ansi blue)$GIT_REPO_PATH/etc/database/migrations/$MIGRATION$(ansi reset)"
		MIGRATION_ID=$(echo "INSERT INTO $CONF_DB_MIGRATION_BASE.$CONF_DB_MIGRATION_TABLE SET dbm_d_creation = NOW(), dbm_s_version = '$MIGRATION'; SELECT LAST_INSERT_ID()" | MYSQL_PWD="$CONF_DB_PWD" mysql -u $CONF_DB_USER -h $CONF_DB_HOST | tail -1)
		MYSQL_PWD="$CONF_DB_PWD" mysql -u $CONF_DB_USER -h db.skriv.tech < "$GIT_REPO_PATH/etc/database/migrations/$MIGRATION"
		echo "UPDATE $CONF_DB_MIGRATION_BASE.$CONF_DB_MIGRATION_TABLE SET dbm_d_done = NOW() WHERE dbm_i_id = '$MIGRATION_ID'" | MYSQL_PWD="$CONF_DB_PWD" mysql -u $CONF_DB_USER -h $CONF_DB_HOST
	done
	echo "$(ansi green)Done$(ansi reset)"
}

# _install_config_apache()
# Generation and installation of Apache files.
_install_config_apache() {
	if [ "$CONF_APACHE_FILES" = "" ]; then
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
	for _CONF_FILE in $CONF_APACHE_FILES; do
		echo "$(ansi blue)> $_CONF_FILE$(ansi reset)"
		if [ -e "${_CONF_FILE}.gen" ]; then
			echo -n "$(ansi dim)+ Generating... $(ansi reset)"
			if [ ! -x "$_CONF_FILE.gen" ]; then
				chmod +x "$_CONF_FILE.gen"
			fi
			"${_CONF_FILE}.gen" "${DPK_OPTIONS["platform"]}" "${DPK_OPTIONS["tag"]}" > "$_CONF_FILE"
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
	if [ "$CONF_INSTALL_FILES_777" != "" ]; then
		echo "$(ansi bold)Setting files access rights$(ansi reset)"
		for _FILE in $CONF_INSTALL_FILES_777; do
			echo "$(ansi dim)> $_FILE$(ansi reset)"
			sudo chmod -R 777 "$_FILE"
			if [ -d "$_FILE" ]; then
				git checkout -- "$(find "$_FILE" -name ".gitignore")" > /dev/null
			fi
		done
	fi
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
			"${_FILE}.gen" "${DPK_OPTIONS["platform"]}" "${DPK_OPTIONS["tag"]}" > "$_FILE"
		done
	fi
}

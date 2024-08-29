#!/usr/bin/env bash

# "adduser" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="adduser"

# Rule's section (for documentation).
RULE_SECTION="System administration"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS="app name"

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="admin"

# Definition of configuration associative arrays.
declare -A CONF_ADDUSER_DATABASE

# Show help for this rule.
rule_help_adduser() {
	echo "   dpk $(ansi bold)aduser$(ansi reset) --app=\"$(ansi dim)app_name$(ansi reset)\" --name=\"$(ansi dim)John Doe$(ansi reset)\" $(ansi dim)[--admin]$(ansi reset)"
	echo "       $(ansi dim)Add a new user in database.$(ansi reset)"
	echo "       --app:      $(ansi dim)Application name.$(ansi reset)"
	echo "       --email:    $(ansi dim)User's email address.$(ansi reset)"
	echo "       --name:     $(ansi dim)User's full name.$(ansi reset)"
	echo "       --admin:    $(ansi dim)(Optional) Give administrator rights.$(ansi reset)"
	echo "       $(ansi yellow)⚠ Needs to find the parameters $(ansi reset)CONF_DB_HOST$(ansi yellow), $(ansi reset)CONF_DB_PORT$(ansi yellow), $(ansi reset)CONF_DB_USER$(ansi yellow) and $(ansi reset)CONF_DB_PWD$(ansi yellow) in the configuration file.$(ansi reset)"
}

# Execution of the rule.
rule_exec_adduser() {
	check_dbhost
	APP="${DPK_OPT["app"]}"
	NAME="${DPK_OPT["name"]}"
	if [ "$NAME" = "" ] || [ "$NAME" = "1" ] || [ "$NAME" = "name" ]; then
		abort "Empty name parameter."
	fi
	DB="${CONF_ADDUSER_DATABASE["$APP"]}"
	if [ "$DB" = "" ]; then
		abort "Unknown application."
	fi
	IS_ADMIN="FALSE"
	if [ "${DPK_OPT["admin"]}" != "" ]; then
		IS_ADMIN="TRUE"
	fi
	SQL="INSERT INTO $DB.User
	     SET creationDate = NOW(),
	         name = '$NAME',
	         admin = $IS_ADMIN";
	_adduser_sql "$SQL"
}

# Private function.
_adduser_sql() {
	echo "$1" | MYSQL_PWD="$CONF_DB_PWD" mysql -u $CONF_DB_USER -h $CONF_DB_HOST -P $CONF_DB_PORT
}


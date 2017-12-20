#!/bin/bash

# "adduser" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="adduser"

# Rule's section (for documentation).
RULE_SECTION="System administration"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS="name email"

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="admin"

# Show help for this rule.
rule_help_adduser() {
	echo "   dpk $(ansi bold)aduser$(ansi reset) --email=\"$(ansi dim)john.doe@domain.com$(ansi reset)\" --name=\"$(ansi dim)John Doe$(ansi reset)\"$(ansi reset)"
	echo "       $(ansi dim)Add a new user in database.$(ansi reset)"
	echo "       --email:    $(ansi dim)User's email address.$(ansi reset)"
	echo "       --name:     $(ansi dim)User's full name.$(ansi reset)"
	echo "       --admin:    $(ansi dim)(Optional) Give administrator rights.$(ansi reset)"
	echo "       $(ansi yellow)⚠ Needs to find the parameters $(ansi reset)CONF_DB_HOST$(ansi yellow), $(ansi reset)CONF_DB_USER$(ansi yellow) and $(ansi reset)CONF_DB_PWD$(ansi yellow) in the configuration file.$(ansi reset)"
}

# Execution of the rule
rule_exec_adduser() {
	check_dbhost
	EMAIL="${DPK_OPT["email"]}"
	NAME="${DPK_OPT["name"]}"
	IS_ADMIN="FALSE"
	if [ "$EMAIL" = "" ] || [ "$EMAIL" = "1" ] || [ "$EMAIL" = "email" ]; then
		abort "Empty email parameter."
	fi
	if [ "$NAME" = "" ] || [ "$NAME" = "1" ] || [ "$NAME" = "name" ]; then
		abort "Empty name parameter."
	fi
	if [ "${DPK_OPT["admin"]}" != "" ]; then
		IS_ADMIN="TRUE"
	fi
	SQL="INSERT INTO Base.User
	     SET creationDate = NOW(),
	         email = '$EMAIL',
	         name = '$NAME',
	         admin = $IS_ADMIN";
	echo "$SQL" | MYSQL_PWD="$CONF_DB_PWD" mysql -u $CONF_DB_USER -h $CONF_DB_HOST
}


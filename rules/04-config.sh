#!/bin/bash

# "config" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="config"

# Rule's section (for documentation).
RULE_SECTION="Tag management"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="platform tag"

# Show help for this rule.
rule_help_config() {
	echo "   dpk $(ansi bold)config$(ansi reset) $(ansi dim)[$(ansi reset)--platform$(ansi dim)=dev|test|prod] [$(ansi reset)--tag$(ansi dim)=$CONF_GIT_MAIN|X.Y.Z]$(ansi reset)"
	echo "       $(ansi dim)Set files and directories access rights. Generate configuration files.$(ansi reset)"
	echo "       $(ansi dim)Subset of the $(ansi reset)install$(ansi dim) rule.$(ansi reset)"
	echo "       $(ansi yellow)⚠ Needs sudo rights$(ansi reset)"
}

# Execution of the rule
rule_exec_config() {
	check_sudo
	check_tag
	check_platform
	# execute pre-config scripts
	_config_pre_scripts
	# install crontab
	_install_crontab
	# Apache configuration
	_install_config_apache
	# files configuration
	_install_config_files
	# execute post-config scripts
	_config_post_scripts
}

# _config_pre_scripts()
# Execute pre-config scripts.
_config_pre_scripts() {
	if [ "$CONF_CONFIG_SCRIPTS_PRE" = "" ]; then
		return
	fi
	echo "$(ansi bold)Execute pre-config scripts$(ansi reset)"
	for _SCRIPT in $CONF_CONFIG_SCRIPTS_PRE; do
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

# _config_post_scripts()
# Execute post-config scripts.
_config_post_scripts() {
	if [ "$CONF_CONFIG_SCRIPTS_POST" = "" ]; then
		return
	fi
	echo "$(ansi bold)Execute post-config scripts$(ansi reset)"
	for _SCRIPT in $CONF_CONFIG_SCRIPTS_POST; do
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


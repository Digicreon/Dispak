#!/bin/bash

# "config" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="config"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="platform tag"

# Show help for this rule.
rule_help_config() {
	echo "  dpk $(ansi bold)config$(ansi reset) $(ansi dim)[--platform=dev|test|prod]$(ansi reset) $(ansi dim)[--tag=master|X.Y.Z]$(ansi reset)"
	echo "      $(ansi dim)Set files and directories access rights. Generate configuration files.$(ansi reset)"
	echo "      $(ansi dim)Subset of the $(ansi reset)install$(ansi dim) rule.$(ansi reset)"
	echo "      $(ansi yellow)⚠ Needs sudo rights$(ansi reset)"
}

# Execution of the rule
rule_exec_config() {
	check_sudo
	check_tag
	check_platform
	# install crontab
	_install_crontab
	# Apache configuration
	_install_config_apache
	# files configuration
	_install_config_files
}

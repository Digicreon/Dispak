#!/usr/bin/env bash

# "minimal" example rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="minimal"

# Show help for this rule.
rule_help_minimal() {
	echo "   dpk $(ansi bold)minimal$(ansi reset)"
	echo "       $(ansi dim)Minimal rule that displays the current user login and the current working directory.$(ansi reset)"
}

# Execution of the rule
rule_exec_minimal() {
	USER_LOGIN="$(id -un)"
	WORKING_DIR="$(pwd)"
	dpk_echo "Current user login:        $(ansi blue)$USER_LOGIN$(ansi reset)"
	dpk_echo "Current working directory: $(ansi yellow)$WORKING_DIR$(ansi reset)"
}

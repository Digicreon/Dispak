#!/bin/bash

# "origin" rule for Dispak
# © 2023, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="origin"

# Rule's section (for documentation).
RULE_SECTION="Development"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS=""

# Show help for this rule.
rule_help_origin() {
	echo "   dpk $(ansi bold)origin$(ansi reset)"
	echo "       $(ansi dim)Show the origin URL of the repository's remote.$(ansi reset)"
}

# Execution of the rule
rule_exec_origin() {
	check_git
	git config --get remote.origin.url
}


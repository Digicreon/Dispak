#!/bin/bash

# "help" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name
RULE_NAME="help"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS=""

# Does this rule need to be executed inside a git repository?
RULE_NEED_GIT=0

# Show help for this rule.
rule_help_help() {
	# colon is the "do nothing" operator
	:
}

# Execution of this rule
rule_exec_help() {
	echo
	echo " $(ansi rev)                                                                     $(ansi reset)"
	echo " $(ansi rev) $(ansi reset)                                                                   $(ansi rev) $(ansi reset)"
	echo " $(ansi rev) $(ansi reset) $(ansi rev blue)                                                                 $(ansi reset) $(ansi rev) $(ansi reset)"
	echo " $(ansi rev) $(ansi reset) $(ansi rev blue)                             DISPAK                              $(ansi reset) $(ansi rev) $(ansi reset)"
	echo " $(ansi rev) $(ansi reset) $(ansi rev blue)                                                                 $(ansi reset) $(ansi rev) $(ansi reset)"
	echo " $(ansi rev) $(ansi reset)                                                                   $(ansi rev) $(ansi reset)"
	echo " $(ansi rev)                                                                     $(ansi reset)"
	echo
	for SECTION in "${!_DPK_RULES[@]}"; do
		if [ ${#_DPK_RULES[@]} -gt 1 ]; then
			echo " $(ansi under)$SECTION$(ansi reset)"
		fi
		for RULE in ${_DPK_RULES["$SECTION"]}; do
			if [ "$RULE" = "help" ]; then
				continue;
			fi
			HELP_FUNCTION="rule_help_${RULE}"
			$HELP_FUNCTION
			echo
		done
	done
}

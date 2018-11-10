#!/bin/bash

# "help" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name
RULE_NAME="help"

# Rule's section (for documentation).
RULE_SECTION=""

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS=""

# Show help for this rule.
rule_help_help() {
	# colon is the "do nothing" operator
	:
}

# Execution of this rule
rule_exec_help() {
	if [ "$1" != "" ]; then
		HELP_FUNCTION="rule_help_$1"
		$HELP_FUNCTION
		return
	fi
	echo
	echo " $(ansi rev)                                                                       $(ansi reset)"
	echo " $(ansi rev)  $(ansi reset)                                                                   $(ansi rev)  $(ansi reset)"
	echo " $(ansi rev)  $(ansi reset)  $(ansi rev blue)                                                               $(ansi reset)  $(ansi rev)  $(ansi reset)"
	echo " $(ansi rev)  $(ansi reset)  $(ansi rev blue)$(ansi bold)                            DISPAK                             $(ansi reset)  $(ansi rev)  $(ansi reset)"
	echo " $(ansi rev)  $(ansi reset)  $(ansi rev blue)                                                               $(ansi reset)  $(ansi rev)  $(ansi reset)"
	echo " $(ansi rev)  $(ansi reset)                                                                   $(ansi rev)  $(ansi reset)"
	echo " $(ansi rev)                                                                       $(ansi reset)"
	echo
	if [ "$COMMAND" == "" ]; then
		echo " $(ansi dim)For detailed information about all commands:$(ansi reset) $(ansi bold)dpk help$(ansi reset)"
		echo " $(ansi dim)For detailed information about one command:$(ansi reset)  $(ansi bold)dpk help$(ansi reset) command_name"
		echo
	fi
	for SECTION in "${!_DPK_RULES[@]}"; do
		if [ ${#_DPK_RULES[@]} -gt 1 ]; then
			echo " $(ansi under)$SECTION$(ansi reset)"
		fi
		for RULE in ${_DPK_RULES["$SECTION"]}; do
			if [ "$RULE" = "help" ]; then
				continue;
			fi
			if [ "$COMMAND" == "" ]; then
				echo "   dpk $(ansi bold)${RULE}$(ansi reset)"
			else
				HELP_FUNCTION="rule_help_${RULE}"
				$HELP_FUNCTION
				echo
			fi
		done
		if [ "$COMMAND" == "" ]; then
			echo
		fi
	done
}

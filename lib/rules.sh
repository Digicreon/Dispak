#!/bin/bash

# _dpk_rule_add()
# Add a rule, indexed by its section.
# @param	string	Rule name.
# @param	string	Section name.
_dpk_rule_add() {
	RULE_NAME="$(trim "$1")"
	SECTION_NAME="$(trim "$2")"
	if [ "$SECTION_NAME" = "" ]; then
		SECTION_NAME="Default"
	fi
	SECTION_RULES="${_DPK_RULES["$SECTION_NAME"]} $RULE_NAME"
	_DPK_RULES["$SECTION_NAME"]="$(trim "$SECTION_RULES")"
}

# _dpk_rule_mandatory_params()
# Add CLI mandatory parameters for a given rule.
# @param	string	The rule's name.
# @param	string	The parameters.
_dpk_rule_mandatory_params() {
	RULE_NAME=$(trim "$1")
	shift
	OPTIONS=""
	for NEW_OPT in $@; do
		OPTIONS="$OPTIONS $NEW_OPT"
	done
	_DPK_RULES_MANDATORY_PARAMS[$RULE_NAME]="$(trim "$OPTIONS")"
}

# _dpk_rule_optional_params()
# Add CLI optional parameters for a given rule.
# @param	string	The rule's name.
# @param	string	The parameters.
_dpk_rule_optional_params() {
	RULE_NAME=$(trim "$1")
	shift
	OPTIONS=""
	for NEW_OPT in $@; do
		OPTIONS="$OPTIONS $NEW_OPT"
	done
	_DPK_RULES_OPTIONAL_PARAMS[$RULE_NAME]="$(trim "$OPTIONS")"
}


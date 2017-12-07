#!/bin/bash

# _dpk_rule_add()
# Add a rule.
# @param	string	Rule name.
_dpk_rule_add() {
	RULE_NAME=$(trim "$1")
	#DPK_RULES[${#DPK_RULES[@]}]="$RULE_NAME"
	_DPK_RULES[$RULE_NAME]=$RULE_NAME
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


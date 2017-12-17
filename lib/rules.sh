#!/bin/bash

# _dpk_import_rules()
# Import the rule files from a directory.
# @param	string	Path to the directory which contains the rules files.
_dpk_import_rules() {
	for FILE in "$1"/*.sh ; do
		RULE_NAME=""
		RULE_SECTION=""
		RULE_MANDATORY_PARAMS=""
		RULE_OPTIONAL_PARAMS=""
		. "$FILE"
		if [ "$RULE_NAME" != "" ]; then
			_dpk_rule_add $RULE_NAME "$RULE_SECTION"
			_dpk_rule_mandatory_params $RULE_NAME $RULE_MANDATORY_PARAMS
			_dpk_rule_optional_params $RULE_NAME $RULE_OPTIONAL_PARAMS
		fi
	done
}

# _dpk_rule_add()
# Add a rule, indexed by its section.
# @param	string	Rule name.
# @param	string	Section name.
_dpk_rule_add() {
	RULE_NAME="$(trim "$1")"
	SECTION_NAME="$(trim "$2")"
	if [ "$SECTION_NAME" = "" ]; then
		if [ "$CONF_DEFAULT_SECTION" != "" ]; then
			SECTION_NAME="$CONF_DEFAULT_SECTION"
		else
			SECTION_NAME="Default"
		fi
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


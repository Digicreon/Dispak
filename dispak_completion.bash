#!/bin/bash

# Bash completion script.
#
# @copyright	© 2018, Amaury Bouchard
# @link		https://debian-administration.org/article/316/An_introduction_to_bash_completion_part_1

_dpk() {
	# fetch parameters
	local CUR PREV PREV2 OPTS
	CUR="${COMP_WORDS[COMP_CWORD]}"
	PREV="${COMP_WORDS[COMP_CWORD-1]}"
	PREV2="${COMP_WORDS[COMP_CWORD-2]}"
	# config
	_ACTIONS="help branch tags pkg install config"
	declare -A _ACTIONS_OPT
	_ACTIONS_OPT["help"]="branch tags pkg install config"
	_ACTIONS_OPT["branch"]="--list --create --remove --merge --backport --tag="
	_ACTIONS_OPT["tags"]="--all"
	_ACTIONS_OPT["pkg"]="--tag="
	_ACTIONS_OPT["install"]="--platform=dev --platform=test --platform=prod --tag=master --tag= --no-apache --no-crontab --no-db-migration"
	_ACTIONS_OPT["config"]="--platform=dev --platform=test --platform=prod --tag=master --tag="
	COMPREPLY=()
	if [ "$COMP_CWORD" = "1" ]; then
		OPTS="$_ACTIONS"
	elif [ "$CUR" = "--platform" ]; then
		OPTS="--platform=dev --platform=test --platform=prod"
	elif [ "$CUR" = "--tag" ]; then
		OPTS="--tag="
	elif [ "$CUR" = "=" ]; then
		CUR=""
		if [ "$PREV" = "--platform" ]; then
			OPTS="dev test prod"
		elif [ "$PREV" = "--tag" ]; then
			OPTS="master"
		fi
	elif [ "$PREV" = "=" ]; then
		if [ "$PREV2" = "--platform" ]; then
			OPTS="dev test prod"
		elif [ "$PREV2" = "--tag" ]; then
			OPTS="master"
		fi
	else
		ACTION="${COMP_WORDS[1]}"
		for _ACT in $_ACTIONS; do
			if [ "$_ACT" = "$ACTION" ]; then
				OPTS="${_ACTIONS_OPT["$ACTION"]}"
				break
			fi
		done
	fi
	COMPREPLY=( $(compgen -W "${OPTS}" -- ${CUR}) )
	return 0
}
complete -F _dpk dpk

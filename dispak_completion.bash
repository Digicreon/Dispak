#!/usr/bin/env bash

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
	_ACTIONS="help branch tags pkg install config origin"
	declare -A _ACTIONS_OPT
	_ACTIONS_OPT["help"]="branch tags pkg install config origin"
	_ACTIONS_OPT["branch"]="--list --graph --create --remove --merge --backport --rebase --rename --prune --from= --tag="
	_ACTIONS_OPT["tags"]="--all"
	_ACTIONS_OPT["pkg"]="--tag="
	_ACTIONS_OPT["install"]="--platform=dev --platform=test --platform=prod --tag=main --tag= --no-apache --no-crontab --no-xinetd --no-supervisor --no-systemd --no-db-migration"
	_ACTIONS_OPT["config"]="--platform=dev --platform=test --platform=prod --tag=main --tag="
	COMPREPLY=()
	if [ "$COMP_CWORD" = "1" ]; then
		OPTS="$_ACTIONS"
	elif [ "$CUR" = "--platform" ]; then
		OPTS="--platform=dev --platform=test --platform=prod"
	elif [ "$CUR" = "--tag" ]; then
		OPTS="--tag="
	elif [ "$CUR" = "--from" ]; then
		OPTS="--from="
	elif [ "$CUR" = "=" ]; then
		CUR=""
		if [ "$PREV" = "--platform" ]; then
			OPTS="dev test prod"
		elif [ "$PREV" = "--tag" ]; then
			OPTS="main"
		elif [ "$PREV" = "--from" ]; then
			OPTS="$(git branch -r 2> /dev/null | grep -v -- '->' | sed 's|^ *origin/||')"
		fi
	elif [ "$PREV" = "=" ]; then
		if [ "$PREV2" = "--platform" ]; then
			OPTS="dev test prod"
		elif [ "$PREV2" = "--tag" ]; then
			OPTS="main"
		elif [ "$PREV2" = "--from" ]; then
			OPTS="$(git branch -r 2> /dev/null | grep -v -- '->' | sed 's|^ *origin/||')"
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

#!/usr/bin/env bash

# "origin" rule for Dispak
# © 2023, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="origin"

# Rule's section (for documentation).
RULE_SECTION="Development"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="branch"

# Show help for this rule.
rule_help_origin() {
	echo "   dpk $(ansi bold)origin$(ansi reset) $(ansi dim)[$(ansi reset)--branch$(ansi dim)|$(ansi reset)--branch$(ansi dim)=branch_name]$(ansi reset)"
	echo "       $(ansi dim)Show the origin URL of the repository's remote.$(ansi reset)"
	echo "       --branch   $(ansi dim)Show the branch from which the current branch (or the given branch) was created,$(ansi reset)"
	echo "                  $(ansi dim)with the number of commits ahead and behind this parent branch.$(ansi reset)"
}

# Execution of the rule
rule_exec_origin() {
	check_git
	if [ -v DPK_OPT["branch"] ]; then
		_origin_branch
	else
		git config --get remote.origin.url
	fi
}

# _origin_branch()
# Show the branch from which a branch was created, with the numbers of commits ahead and behind.
_origin_branch() {
	git_fetch
	# get the branch to analyze (the current branch if no branch name was given)
	BRANCH="${DPK_OPT["branch"]}"
	if [ "$BRANCH" = "" ]; then
		BRANCH="$(git_get_current_branch)"
		if [ "$BRANCH" = "HEAD" ]; then
			abort "$(ansi red)Not currently on a branch.$(ansi reset)"
		fi
	fi
	# check the branch name (can't be 'main')
	if [ "$BRANCH" = "$CONF_GIT_MAIN" ]; then
		abort "$(ansi red)The '$CONF_GIT_MAIN' branch was not created from another branch.$(ansi reset)"
	fi
	# get the branch reference (local branch if it exists, remote branch otherwise)
	BRANCH_REF="$BRANCH"
	if [ "$(git rev-parse --verify --quiet "refs/heads/$BRANCH")" = "" ]; then
		if [ "$(git rev-parse --verify --quiet "refs/remotes/origin/$BRANCH")" = "" ]; then
			abort "$(ansi red)The branch '$BRANCH' doesn't exist.$(ansi reset)"
		fi
		BRANCH_REF="origin/$BRANCH"
	fi
	# find the parent branch
	PARENT_SRC="$(git_get_parent_branch "$BRANCH")"
	if [ "$PARENT_SRC" = "" ]; then
		abort "$(ansi red)Unable to find the branch from which '$BRANCH' was created.$(ansi reset)"
	fi
	# count the commits ahead and behind the parent branch
	COUNT_AHEAD="$(git rev-list --right-only --count "origin/$PARENT_SRC...$BRANCH_REF")"
	COUNT_BEHIND="$(git rev-list --left-only --count "origin/$PARENT_SRC...$BRANCH_REF")"
	echo "$(ansi bold)Branch:$(ansi reset)        $BRANCH"
	echo "$(ansi bold)Created from:$(ansi reset)  $PARENT_SRC"
	echo "$(ansi bold)Ahead:$(ansi reset)         $COUNT_AHEAD commit(s)"
	echo "$(ansi bold)Behind:$(ansi reset)        $COUNT_BEHIND commit(s)"
}


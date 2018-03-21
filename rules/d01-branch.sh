#!/bin/bash

# "branch" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="branch"

# Rule's section (for documentation).
RULE_SECTION="Development"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="list create remove merge backport"

# Show help for this rule.
rule_help_branch() {
	echo "   dpk $(ansi bold)branch$(ansi reset) $(ansi dim)[$(ansi reset)--list$(ansi dim)] [$(ansi reset)--create$(ansi dim)=branch_name] [$(ansi reset)--remove$(ansi dim)=branch_name] [$(ansi reset)--merge$(ansi dim)] [$(ansi reset)--backport$(ansi dim)] [--tag=X.Y.Z]$(ansi reset)"
	echo "       $(ansi dim)Manage branches. At least one of these parameters must be given:$(ansi reset)"
	echo "       --list     $(ansi dim)List all existing branches, with the tag from wich they were created.$(ansi reset)"
	echo "       --create   $(ansi dim)Name of the branch to create (locally and remotely). Move to the branch after its creation.$(ansi reset)"
	echo "                  $(ansi dim)Branches are always created from the $(ansi reset)master$(ansi dim) branch.$(ansi reset)"
	echo "                  $(ansi dim)The new branch could be created from a given tag, using the $(ansi reset)--tag$(ansi dim) parameter.$(ansi reset)"
	echo "       --remove   $(ansi dim)Name of the branch to delete.$(ansi reset)"
	echo "       --merge    $(ansi dim)Merge the current branch on the $(ansi reset)master$(ansi dim) branch.$(ansi reset)"
	echo "       --backport $(ansi dim)Merge the $(ansi reset)master$(ansi dim) branch on the current branch.$(ansi reset)"
}

# Execution of the rule
rule_exec_branch() {
	check_git
	git_fetch
	if [ "${DPK_OPT["list"]}" != "" ]; then
		# list branches
		_branch_list
	elif [ "${DPK_OPT["create"]}" != "" ]; then
		# create new branch
		_branch_create
	elif [ "${DPK_OPT["remove"]}" != "" ]; then
		# delete branch
		_branch_remove
	elif [ "${DPK_OPT["merge"]}" != "" ]; then
		# merge
		_branch_merge
	elif [ "${DPK_OPT["backport"]}" != "" ]; then
		# backport
		_branch_backport
	else
		echo "$(ansi red)No option given.$(ansi reset)"
		rule_help_branch
		abort
	fi
}

# _branch_list()
# List all existing branches, with the tag from wich they were created.
_branch_list() {
	CURRENT_BRANCH="$(get_git_branch)"
	for BRANCH in `git ls-remote --heads 2> /dev/null | sed 's/.*\///'`; do
		if [ "$BRANCH" = "$CURRENT_BRANCH" ]; then
			echo "* $(ansi red)$BRANCH$(ansi reset)"
		else
			echo "  $BRANCH"
		fi
	done
}

# _branch_create()
# Create a new branch.
_branch_create() {
	# check if a branch already exists with this name
	if [ "$(git branch | grep "${DPK_OPT["create"]}")" != "" ]; then
		abort "$(ansi red)A branch already exists with this name.$(ansi reset)"
	fi
	if [ "$(get_git_branch)" != "master" ]; then
		echo "$(ansi bold)Move to master branch$(ansi reset)"
		git checkout master
	fi
	# was a tag given?
	if [ "${DPK_OPT["tag"]}" != "" ]; then
		# to create branch from a given tag, check if the given tag exists
		check_tag
	fi
	echo "$(ansi bold)Create the new branch$(ansi reset)"
	if [ "${DPK_OPT["tag"]}" = "" ]; then
		git checkout -b "${DPK_OPT["create"]}"
	else
		git checkout -b "${DPK_OPT["create"]}" "${DPK_OPT["tag"]}"
	fi
	echo "$(ansi bold)Push the branch to remote git repository$(ansi reset)"
	git push --set-upstream origin "${DPK_OPT["create"]}"
}

# _branch_remove()
# Delete a branch.
_branch_remove() {
	# check if a branch exists with this name
	if [ "$(git branch | grep "${DPK_OPT["remove"]}")" = "" ]; then
		abort "$(ansi red)No branch exists with this name.$(ansi reset)"
	fi
	if [ "$(get_git_branch)" != "master" ]; then
		echo "$(ansi bold)Move to master branch$(ansi reset)"
		git checkout master
	fi
	echo "$(ansi bold)Delete the branch locally$(ansi reset)"
	git branch -d "${DPK_OPT["remove"]}"
	echo "$(ansi bold)Delete the branch on the remote git repository$(ansi reset)"
	git push origin ":${DPK_OPT["remove"]}"
}

# _branch_merge()
# Merge the current branch on the master branch.
_branch_merge() {
	check_git_branch
	check_git_clean
	check_git_pushed
	BRANCH="$(get_git_branch)"
	echo "$(ansi bold)Checking out to master branch$(ansi reset)"
	git checkout master
	git pull
	echo "$(ansi bold)Merging '$BRANCH'$(ansi reset)"
	git merge "$BRANCH"
	echo "$(ansi bold)Pushing to remote git repository$(ansi reset)"
	git push origin master
	echo "$(ansi bold)Checking out back to branch '$BRANCH'$(ansi reset)"
	git checkout "$BRANCH"
}

# _branch_backport()
# Merge the master branch on the current branch.
_branch_backport() {
	check_git_branch
	check_git_clean
	check_git_pushed
	BRANCH="$(get_git_branch)"
	echo "$(ansi bold)Updating master branch$(ansi reset)"
	git checkout master
	git pull
	git checkout "$BRANCH"
	echo "$(ansi bold)Merging master branch$(ansi reset)"
	git merge master
	echo "$(ansi bold)Pushing to remote git repository$(ansi reset)"
	git push origin "$BRANCH"
}


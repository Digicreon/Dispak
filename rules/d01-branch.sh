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
RULE_OPTIONAL_PARAMS="create remove"

# Show help for this rule.
rule_help_branch() {
	echo "   dpk $(ansi bold)branch$(ansi reset) $(ansi dim)[$(ansi reset)--list$(ansi dim)] [$(ansi reset)--create$(ansi dim)=branch_name] [$(ansi reset)--remove$(ansi dim)=branch_name] [--tag=X.Y.Z]$(ansi reset)"
	echo "       $(ansi dim)Manage branches. At least one of the parameters must be given:$(ansi reset)"
	echo "       --list   $(ansi dim)List all existing branches, with the tag from wich they were created.$(ansi reset)"
	echo "       --create $(ansi dim)Name of the branch to create (locally and remotely). Move to the branch after its creation.$(ansi reset)"
	echo "                $(ansi dim)Branches are always created from the $(ansi reset)master$(ansi dim) branch.$(ansi reset)"
	echo "                $(ansi dim)The new branch could be created from a given tag, using the $(ansi reset)--tag$(ansi dim) parameter.$(ansi reset)"
	echo "       --remove $(ansi dim)Name of the branch to delete.$(ansi reset)"
}

# Execution of the rule
rule_exec_branch() {
	check_git
	if [ "${DPK_OPT["list"]}" != "" ]; then
		# list branches
		git branch --list
	elif [ "${DPK_OPT["create"]}" != "" ]; then
		# create new branch
		# check if a branch already exists with this name
		if [ "$(git branch | grep "${DPK_OPT["create"]}")" != "" ]; then
			abort "$(ansi red)A branch already exists with this name.$(ansi reset)"
		fi
		if [ "$(git rev-parse --abbrev-ref HEAD)" != "master" ]; then
			echo "$(ansi bold)Move to master branch$(ansi reset)"
			git checkout master
		fi
		# was a tag given?
		if [ "${DPK_OPT["tag"]}" != "" ]; then
			# create branch from a given tag
			check_tag
			echo "$(andi bold)Create the new branch$(ansi reset)"
			git checkout -b "${DPK_OPT["create"]}" "${DPK_OPT["tag"]}"
			echo "$(ansi bold)Push the branch to remote git repository$(ansi reset)"
			git push origin "${DPK_OPT["create"]}"
			return
		fi
		# no tag given
		echo "$(ansi bold)Create the new branch$(ansi reset)"
		git checkout -b "${DPK_OPT["create"]}"
		echo "$(ansi bold)Push the branch to remote git repository$(ansi reset)"
		git push origin "${DPK_OPT["create"]}"
	elif [ "${DPK_OPT["remove"]}" != "" ]; then
		# delete branch
		# check if a branch exists with this name
		if [ "$(git branch | grep "{$DPK_OPT["remove"]}")" = "" ]; then
			abort "$(ansi red)No branch exists with this name.$(ansi reset)"
		fi
		echo "$(ansi bold)Move to master branch$(ansi reset)"
		git checkout master
		echo "$(ansi bold)Delete the branch locally$(ansi reset)"
		git branch -d "${DPK_OPT["remove"]}"
		echo "$(ansi bold)Delete the branch on the remote git repository$(ansi reset)"
		git push origin ":${DPK_OPT["remove"]}"
	fi
}


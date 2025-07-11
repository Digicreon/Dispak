#!/usr/bin/env bash

# "branch" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="branch"

# Rule's section (for documentation).
RULE_SECTION="Development"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="list graph create remove merge backport rebase rename prune"

# Show help for this rule.
rule_help_branch() {
	echo "   dpk $(ansi bold)branch$(ansi reset) $(ansi dim)[$(ansi reset)--list$(ansi dim)] [$(ansi reset)--graph$(ansi dim)] [$(ansi reset)--create$(ansi dim)=branch_name [--tag=X.Y.Z]] [$(ansi reset)--remove$(ansi dim)=branch_name] [$(ansi reset)--merge$(ansi dim)|$(ansi reset)--merge$(ansi dim)=branch_name] [$(ansi reset)--backport$(ansi dim)|$(ansi reset)--backport$(ansi dim)=branch_name] [$(ansi reset)--rebase$(ansi dim)] [$(ansi reset)--rename$(ansi dim)=new_name] [$(ansi reset)--prune$(ansi dim)|$(ansi reset)--prune$(ansi dim)=branch_name]$(ansi reset)"
	echo "       $(ansi dim)Manage branches. One of these parameters must be given:$(ansi reset)"
	echo "       --list     $(ansi dim)List all existing branches, with the tag from wich they were created.$(ansi reset)"
	echo "       --graph    $(ansi dim)Show a graph of the existing branches.$(ansi reset)"
	echo "       --create   $(ansi dim)Name of the branch to create (locally and remotely). Move to the branch after its creation.$(ansi reset)"
	echo "                  $(ansi dim)Branches are always created from the $(ansi reset)$CONF_GIT_MAIN$(ansi dim) branch.$(ansi reset)"
	echo "                  $(ansi dim)Use the $(ansi reset)--tag$(ansi dim) to tell the tag from which the new branch will be created (optional; use the last $(ansi reset)$CONF_GIT_MAIN$(ansi dim) revision if not given).$(ansi reset)"
	echo "       --remove   $(ansi dim)Name of the branch to delete.$(ansi reset)"
	echo "       --merge    $(ansi dim)Merge the current branch on the given branch (or $(ansi reset)$CONF_GIT_MAIN$(ansi dim) if no branch was given).$(ansi reset)"
	echo "       --backport $(ansi dim)Merge the given branch (or $(ansi reset)$CONF_GIT_MAIN$(ansi dim) if no branch was given) on the current branch.$(ansi reset)"
	echo "       --rebase   $(ansi dim)Rebase the current branch from $(ansi reset)$CONF_GIT_MAIN$(ansi dim).$(ansi reset)"
	echo "       --rename   $(ansi dim)Rename the current branch (not the $(ansi reset)$CONF_GIT_MAIN$(ansi dim) branch) with the given name.$(ansi reset)"
	echo "       --prune    $(ansi dim)Remove the given local branch that doesn't remotely exist, or all local-only branches if no branch was given.$(ansi reset)"
}

# Execution of the rule
rule_exec_branch() {
	check_git
	git_fetch
	if [ -v DPK_OPT["list"] ]; then
		# list branches
		_branch_list
	elif [ -v DPK_OPT["graph"] ]; then
		# show branches graph
		_branch_graph
	elif [ -v DPK_OPT["create"] ]; then
		# create new branch
		_branch_create
	elif [ -v DPK_OPT["remove"] ]; then
		# delete branch
		_branch_remove
	elif [ -v DPK_OPT["merge"] ]; then
		# merge
		_branch_merge
	elif [ -v DPK_OPT["backport"] ]; then
		# backport
		_branch_backport
	elif [ -v DPK_OPT["rebase"] ]; then
		# rebase
		_branch_rebase
	elif [ -v DPK_OPT["rename"] ]; then
		# rename
		_branch_rename
	elif [ -v DPK_OPT["prune"] ]; then
		# prune
		_branch_prune
	else
		echo "$(ansi red)No option given.$(ansi reset)"
		rule_help_branch
		abort
	fi
}

# _branch_list()
# List all existing branches, with the tag from wich they were created.
_branch_list() {
	CURRENT_BRANCH="$(git_get_current_branch)"
	# show local branches that doesn't exist remotely
	LOCAL_BRANCHES="$(git_get_branches_local_only)"
	if [ "$LOCAL_BRANCHES" != "" ]; then
		echo "$(ansi bold)$(ansi under)Local branches$(ansi reset)"
		for BRANCH in $LOCAL_BRANCHES; do
			if [ "$BRANCH" = "$CURRENT_BRANCH" ]; then
				echo "* $(ansi red)$BRANCH$(ansi reset)"
			else
				echo "  $BRANCH"
			fi
		done
	fi
	# show remote branches
	REMOTE_BRANCHES="$(git_get_branches)"
	if [ "$LOCAL_BRANCHES" != "" ] && [ "$REMOTE_BRANCHES" != "" ]; then
		echo
		echo "$(ansi bold)$(ansi under)Remote branches$(ansi reset)"
	fi
	if [ "$REMOTE_BRANCHES" != "" ]; then
		for BRANCH in $REMOTE_BRANCHES; do
			LAST_COMMIT_DATE="$(git_get_branch_last_commit_date "origin/$BRANCH")"
			if [ "$BRANCH" = "$CURRENT_BRANCH" ]; then
				printf "$(ansi red)*$(ansi reset) $(ansi dim)%-25s$(ansi reset)\t$(ansi red)%s$(ansi reset)\n" "$LAST_COMMIT_DATE" "$BRANCH"
			else
				printf "  $(ansi dim)%-25s$(ansi reset)\t%s\n" "$LAST_COMMIT_DATE" "$BRANCH"
			fi
		done
	fi
	return
}

# _branch_graph()
# Show a graph of the existing branches.
_branch_graph() {
	git log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --all
}

# _branch_create()
# Create a new branch.
_branch_create() {
	# get the branch to create
	CREATE_BRANCH="${DPK_OPT["create"]}"
	if [ ! "$CREATE_BRANCH" ]; then
		abort "$(ansi red)Empty branch name.$(ansi reset)"
	fi
	# check the branch name (can't be 'main')
	if [ "$CREATE_BRANCH" = "$CONF_GIT_MAIN" ]; then
		abort "$(ansi red)Unable to create a '$CONF_GIT_MAIN' branch.$(ansi reset)"
	fi
	# check if a branch already exists with this name
	if [ "$(git_get_branches_local_only | grep "$CREATE_BRANCH" | wc -l)" -ne 0 ]; then
		abort "$(ansi red)A '$CREATE_BRANCH' local branch already exists.$(ansi reset)"
	fi
	if [ "$(git_get_branches | grep "$CREATE_BRANCH" | wc -l)" -ne 0 ]; then
		abort "$(ansi red)A '$CREATE_BRANCH' branch already exists.$(ansi reset)"
	fi
	# move to 'main' branch if needed
	if [ "$(git_get_current_branch)" != "$CONF_GIT_MAIN" ]; then
		echo "$(ansi bold)Move to '$CONF_GIT_MAIN' branch$(ansi reset)"
		git checkout "$CONF_GIT_MAIN"
	fi
	# was a tag given?
	TAG_SRC="${DPK_OPT["tag"]}"
	if [ "$TAG_SRC" != "" ]; then
		# to create branch from a given tag, check if the given tag exists
		check_tag
	fi
	# create the new branch
	if [ "$TAG_SRC" = "" ]; then
		echo "$(ansi bold)Create the new branch (from '$CONF_GIT_MAIN' branch)$(ansi reset)"
		git checkout -b "$CREATE_BRANCH"
	else
		echo "$(ansi bold)Create the new branch (from tag '$TAG_SRC' on '$CONF_GIT_MAIN' branch)$(ansi reset)"
		git checkout -b "$CREATE_BRANCH" "$TAG_SRC"
	fi
	echo "$(ansi bold)Push the branch to remote git repository$(ansi reset)"
	git push --set-upstream origin "$CREATE_BRANCH"
}

# _branch_remove()
# Delete a branch.
_branch_remove() {
	# get the branch to remove and check its name
	RM_BRANCH="${DPK_OPT["remove"]}"
	if [ ! "$RM_BRANCH" ]; then
		abort "$(ansi red)Empty branch name.$(ansi reset)"
	fi
	# check the branch name (can't be 'main')
	if [ "$RM_BRANCH" = "$CONF_GIT_MAIN" ]; then
		abort "$(ansi red)Unable to remove the '$CONF_GIT_MAIN' branch.$(ansi reset)"
	fi
	# check if a branch exists with this name
	if [ "$(git_get_branches_local_and_remote | grep "$RM_BRANCH" | wc -l)" -eq 0 ]; then
		abort "$(ansi red) No '$RM_BRANCH' branch exists.$(ansi reset)"
	fi
	# check if the branch exists remotely
	IS_REMOTE_BRANCH="no"
	if [ "$(git_get_branches | grep "$RM_BRANCH" | wc -l)" -ne 0 ]; then
		IS_REMOTE_BRANCH="yes"
	fi
	# move to 'main' branch
	echo "$(ansi bold)Move to '$CONF_GIT_MAIN' branch$(ansi reset)"
	git checkout "$CONF_GIT_MAIN"
	# delete the local branch
	if [ "$(git branch | grep "$RM_BRANCH" | wc -l)" -ne 0 ]; then
		echo "$(ansi bold)Delete the '$RM_BRANCH' branch locally$(ansi reset)"
		git branch -D "$RM_BRANCH"
	fi
	# delete the remote branch if it exists
	if [ "$IS_REMOTE_BRANCH" = "yes" ]; then
		echo "$(ansi bold)Delete the '$RM_BRANCH' branch on the remote git repository$(ansi reset)"
		git push origin ":$RM_BRANCH"
	fi
}

# _branch_merge()
# Merge the current branch on the given branch (defaults to 'main').
_branch_merge() {
	check_git_branch
	check_git_clean
	check_git_pushed
	# get the current branch
	BRANCH="$(git_get_current_branch)"
	# get the branch to merge onto
	BRANCH_DEST="$CONF_GIT_MAIN"
	if [ "${DPK_OPT["merge"]}" != "" ]; then
		# a branch was given
		BRANCH_DEST="${DPK_OPT["merge"]}"
		# check if this branch exists
		if [ "$(git_get_branches | grep "$BRANCH_DEST" | wc -l)" -eq 0 ]; then
			abort "$(ansi red)The branch '$BRANCH_DEST' doesn't exist.$(ansi reset)"
		fi
	fi
	# check the source and destination are different
	if [ "$BRANCH" = "$BRANCH_DEST" ]; then
		abort "$(ansi red)Unable to merge the '$BRANCH' branch on itself.$(ansi reset)"
	fi
	# merge operations
	echo "$(ansi bold)Checking out to '$BRANCH_DEST' branch$(ansi reset)"
	git checkout "$BRANCH_DEST"
	git pull
	echo "$(ansi bold)Merging '$BRANCH'$(ansi reset)"
	git merge "$BRANCH" -Xignore-space-at-eol
	echo "$(ansi bold)Pushing to remote git repository$(ansi reset)"
	git push origin "$BRANCH_DEST"
	echo "$(ansi bold)Checking out back to branch '$BRANCH'$(ansi reset)"
	git checkout "$BRANCH"
}

# _branch_backport()
# Merge the given branch (defaults to 'main') on the current branch.
_branch_backport() {
	check_git_branch
	check_git_clean
	check_git_pushed
	# get the current branch
	BRANCH="$(git_get_current_branch)"
	# get the branch to merge on the current branch
	BRANCH_SRC="$CONF_GIT_MAIN"
	if [ "${DPK_OPT["backport"]}" != "" ]; then
		# a branch was given
		BRANCH_SRC="${DPK_OPT["backport"]}"
		# check if this branch exists
		if [ "$(git_get_branches | grep "$BRANCH_SRC" | wc -l)" -eq 0 ]; then
			abort "$(ansi red)The branch '$BRANCH_SRC' doesn't exist.$(ansi reset)"
		fi
	fi
	# check the source and destination are different
	if [ "$BRANCH" = "$BRANCH_SRC" ]; then
		abort "$(ansi red)Unable to backport the '$BRANCH' branch on itself.$(ansi reset)"
	fi
	# backport operations
	echo "$(ansi bold)Updating '$BRANCH_SRC' branch$(ansi reset)"
	git checkout "$BRANCH_SRC"
	git pull
	echo "$(ansi bold)Checking out back to branch '$BRANCH'$(ansi reset)"
	git checkout "$BRANCH"
	echo "$(ansi bold)Merging '$BRANCH_SRC' branch$(ansi reset)"
	git merge "$BRANCH_SRC" -Xignore-space-at-eol
	echo "$(ansi bold)Pushing to remote git repository$(ansi reset)"
	git push origin "$BRANCH"
}

# _branch_rebase()
# Rebase the current branch from 'main'.
_branch_rebase() {
	check_git_branch
	check_git_clean
	check_git_pushed
	# get the current branch
	BRANCH="$(git_get_current_branch)"
	# get the branch to rebase onto
	BRANCH_SRC="$CONF_GIT_MAIN"
	if [ "${DPK_OPT["rebase"]}" != "" ]; then
		# a branch was given
		BRANCH_SRC="${DPK_OPT["rebase"]}"
		# check if this branch exists
		if [ "$(git_get_branches | grep "$BRANCH_SRC" | wc -l)" -eq 0 ]; then
			abort "$(ansi red)The branch '$BRANCH_SRC' doesn't exist.$(ansi reset)"
		fi
	fi
	# check the source and destination are different
	if [ "$BRANCH" = "$BRANCH_SRC" ]; then
		abort "$(ansi red)Unable to rebase the '$BRANCH' branch on itself.$(ansi reset)"
	fi
	if [ "$BRANCH" = "$CONF_GIT_MAIN" ]; then
		abort "$(ansi red)Unable to rebase '$CONF_GIT_MAIN' branch.$(ansi reset)"
	fi
	# rebase operations
	echo "$(ansi bold)Updating '$CONF_GIT_MAIN' branch$(ansi reset)"
	git checkout "$CONF_GIT_MAIN"
	git pull
	echo "$(ansi bold)Checking out back to branch '$BRANCH'$(ansi reset)"
	git checkout "$BRANCH"
	echo "$(ansi bold)Rebasing '$BRANCH' branch on '$BRANCH_SRC'$(ansi reset)"
	git rebase "$BRANCH_SRC"
	git pull
	echo "$(ansi bold)Pushing to remote git repository$(ansi reset)"
	git push origin "$BRANCH"
}

# _branch_rename()
# Rename the current branch to the given name.
_branch_rename() {
	check_git_branch
	check_git_clean
	check_git_pushed
	# get the current branch name
	OLD_NAME="$(git_get_current_branch)"
	# get the new branch name
	NEW_NAME="${DPK_OPT["backport"]}"
	if [ "$NEW_NAME" = "" ]; then
		abort "$(ansi red)No branch name given.$(ansi reset)"
	fi
	# check if the branch exists
	if [ "$(git_get_branches | grep "$NEW_NAME" | wc -l)" -ne 0 ]; then
		abort "$(ansi red)The branch '$NEW_NAME' already exists.$(ansi reset)"
	fi
	# check the new name is not "main"
	if [ "$NEW_NAME" = "$CONF_GIT_MAIN" ]; then
		abort "$(ansi red)Unable to rename the '$OLD_NAME' branch to '$CONF_GIT_MAIN'.$(ansi reset)"
	fi
	# check the old and new names are different
	if [ "$OLD_NAME" = "$NEW_NAME" ]; then
		abort "$(ansi red)Unable to rename the '$OLD_NAME' branch to itself.$(ansi reset)"
	fi
	# rename operation
	echo "$(ansi bold)Renaming '$OLD_NAME' branch to '$NEW_NAME'$(ansi reset)"
	git branch -m "$NEW_NAME"
	git push origin -u "$NEW_NAME"
	git push origin --delete "$OLD_NAME"
}

# _branch_prune()
# Remove the given local branch that doesn't remotely exist, or all local-only branches if no branch was given.
_branch_prune() {
	CURRENT_BRANCH="$(git_get_current_branch)"
	# get local branches
	LOCAL_BRANCHES="$(git_get_branches_local_only)"
	# check if there are some local-only branches
	if [ "$LOCAL_BRANCHES" = "" ]; then
		abort "$(ansi red)No local-only branches.$(ansi reset)"
	fi
	# check if we are on a local-only branch
	FOUND_GIVEN_BRANCH=0
	for BRANCH in $LOCAL_BRANCHES; do
		if [ "$BRANCH" = "$CURRENT_BRANCH" ]; then
			abort "$(ansi red)Unable to prune while you are on a remote-only branch.$(ansi reset)"
		fi
		if [ "$BRANCH" = "${DPK_OPT["prune"]}" ]; then
			FOUND_GIVEN_BRANCH=1
		fi
	done
	# check the given branch
	if [ "${DPK_OPT["prune"]}" != "" ] && [ $FOUND_GIVEN_BRANCH -eq 0 ]; then
		abort "$(ansi red)The given branch '${DPK_OPT["prune"]}' is not a local-only branch.$(ansi reset)"
	fi
	# remove the given local-only branche, or all local-only branches (if no branch was given)
	for BRANCH in $LOCAL_BRANCHES; do
		if [ "${DPK_OPT["prune"]}" = "" ] || [ "${DPK_OPT["prune"]}" = "$BRANCH" ]; then
			git branch --delete $BRANCH
		fi
	done
}


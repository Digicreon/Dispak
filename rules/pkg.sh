#!/bin/bash

# "pkg" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="pkg"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="tag"

# Show help for this rule.
rule_pkg_help() {
	echo "  dpk $(ansi bold)pkg$(ansi reset) $(ansi dim)[--tag=X.Y.Z]$(ansi reset)"
	echo "      $(ansi dim)Create a new tag. Upload files to AWS S3 (see $(ansi reset)s3$(ansi dim) rule) only if the tag is a stable version.$(ansi reset)"
}

# Execution of the rule
rule_pkg_exec() {
	check_git
	check_aws
	check_next_tag
	check_url
	if [ "$(git rev-parse --abbrev-ref HEAD)" != "master" ]; then
		abort "$(ansi red)You have to be on the $(ansi reset)master$(ansi red) branch.$(ansi reset)"
	fi
	if [ -n "$(git status -s)" ]; then
		warn "$(ansi yellow)There is some uncommitted files.$(ansi reset)"
		git status -s
		read -p "Do you want to proceed anyway? [y/N] " ANSWER
		if [ "$ANSWER" != "y" ] && [ "$ANSWER" != "Y" ]; then
			exit 11
		fi
	fi
	if [ -f "$GIT_REPO_PATH/etc/database/migrations/current" ] && [ "$(du "$GIT_REPO_PATH/etc/database/migrations/current" | cut -f1)" != "0" ]; then
		if [ "$(git status -s | grep "^A" | wc -l)" != "0" ]; then
			abort "$(ansi red)Need to commit database migration files, but you have files waiting to be committed.$(ansi reset)"
		fi
		git mv "$GIT_REPO_PATH/etc/database/migrations/current" "$GIT_REPO_PATH/etc/database/migrations/${DPK_OPTIONS["tag"]}"
		touch "$GIT_REPO_PATH/etc/database/migrations/current"
		git add "$GIT_REPO_PATH/etc/database/migrations/${DPK_OPTIONS["tag"]}" "$GIT_REPO_PATH/etc/database/migrations/current"
		git commit -m "Added database migration file for version ${DPK_OPTIONS["tag"]}"
		git push origin master
	fi
	echo "$(ansi bold)Creating local tag '${DPK_OPTIONS["tag"]}'...$(ansi reset)"
	git tag -a ${DPK_OPTIONS["tag"]}
	echo "$(ansi bold)Pushing tag to server...$(ansi reset)"
	git push origin ${DPK_OPTIONS["tag"]}
}

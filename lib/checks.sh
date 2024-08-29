#!/usr/bin/env bash

# check_aws()
# Check if the aws-cli program is installed.
check_aws() {
	which aws > /dev/null
	if [ $? -ne 0 ] ; then
		abort "$(ansi red)No 'aws' CLI program found.
   You need to install the AWS command-line tool to send file to Amazon S3.$(ansi reset)
     Installation:  $(ansi dim)\$ sudo apt install awscli$(ansi reset) (Debian/Ubuntu)
                    $(ansi dim)\$ sudo yum install awscli$(ansi reset) (CentOS/RedHat)
                    $(ansi dim)\$ sudo pip install awscli$(ansi reset) (Python installer)
     Configuration: $(ansi dim)http://docs.aws.amazon.com/fr_fr/cli/latest/userguide/cli-chap-getting-started.html$(ansi reset)
     Usage:         $(ansi dim)http://docs.aws.amazon.com/fr_fr/cli/latest/userguide/cli-chap-using.html$(ansi reset)
  "
	fi
}

# check_dbhost()
# Check if the database host is defined and reachable.
check_dbhost() {
	if [ "$CONF_DB_HOST" = "" ] || [ "$CONF_DB_PORT" = "" ] || [ "$CONF_DB_USER" = "" ] || [ "$CONF_DB_PWD" = "" ]; then
		abort "Empty database configuration."
	fi
	echo "SELECT 1;" | MYSQL_PWD="$CONF_DB_PWD" mysql -u $CONF_DB_USER -h $CONF_DB_HOST -P $CONF_DB_PORT > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		abort "$(ansi red)Database connection error on$(ansi reset) $DATABASE_HOSTNAME $(ansi red).$(ansi reset)"
	fi
}

# check_sudo()
# Check if the user has sudo rights.
check_sudo() {
	sudo echo "$(ansi green)✓ sudo rights checked$(ansi reset)" || exit 3
}

# check_git()
# Check if we are in a git repository. Abort if not.
check_git() {
	git rev-parse --is-inside-work-tree > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		abort "$(ansi red)The command $(ansi reset)$COMMAND$(ansi red) must be executed inside a git repository.$(ansi reset)"
	fi
}

# check_git_master()
# Check if we are on the 'master' branch. Abort if not.
check_git_master() {
	if [ "$(git_get_current_branch)" != "$CONF_GIT_MAIN" ]; then
		abort "$(ansi red)You have to be on the $(ansi reset)$CONF_GIT_MAIN$(ansi red) branch.$(ansi reset)"
	fi
}

# check_git_branch()
# Check if we are on a branch (not the 'master' branch). Abort if not.
check_git_branch() {
	if [ "$(git_get_current_branch)" = "$CONF_GIT_MAIN" ]; then
		abort "$(ansi red)You must not be on the $(ansi reset)$CONF_GIT_MAIN$(ansi red) branch.$(ansi reset)"
	fi
}

# check_git_clean()
# Check if the Git repository is clean (all files are committed, no new file and no modified file).
# @param	bool	Strict mode: If equal 1, abort if there is uncommitted files. Otherwise ask the user.
check_git_clean() {
	if [ "$(git status --porcelain)" = "" ]; then
		# everything is clean
		return
	fi
	if [ "$1" != "" ] && [ "$1" != "0" ]; then
		abort "There is some uncommitted files.
$(git status -s)
"
	fi
	warn "$(ansi yellow)There is some uncommitted files.$(ansi reset)"
	git status -s
	read -p "Do you want to proceed anyway? [y/N] " ANSWER
	if [ "$ANSWER" != "y" ] && [ "$ANSWER" != "Y" ]; then
		abort
	fi
}

# check_git_pushed()
# Check if all files have been pushed to the remote repository. Abort if not.
check_git_pushed() {
	BRANCH="$(git_get_current_branch)"
	if [ "$(git diff --stat origin/$BRANCH..)" != "" ]; then
		warn "$(ansi yellow)Some committed files have not been pushed to the remote git repository.$(ansi reset)"
		git diff --stat origin/$BRANCH..
		echo
		abort "$(ansi red)Please, push them with the command$(ansi reset)
  git push origin $BRANCH
"
	fi
}

# check_platform()
# Check the platform given as a parameter, or detect the platform.
check_platform() {
	if [ "${DPK_OPT["platform"]}" = "dev" ] || [ "${DPK_OPT["platform"]}" = "test" ] || [ "${DPK_OPT["platform"]}" = "prod" ]; then
		return
	fi
	if [ "$CONF_PLATFORM" = "dev" ] || [ "$CONF_PLATFORM" = "test" ] || [ "$CONF_PLATFORM" = "prod" ]; then
		DPK_OPT["platform"]="$CONF_PLATFORM"
		return
	fi
	HOSTNAME=$(hostname)
	if [ "${CONF_PLATFORMS[$HOSTNAME]}" = "dev" ] || [ "${CONF_PLATFORMS[$HOSTNAME]}" = "test" ] || [ "${CONF_PLATFORMS[$HOSTNAME]}" = "prod" ]; then
		DPK_OPT["platform"]="${CONF_PLATFORMS[$HOSTNAME]}"
		return
	fi
	echo "$HOSTNAME" | grep -Eq "^test[0-9]*$|^preprod[0-9]*$|^pprod[0-9]*$"
	if [ $? -eq 0 ]; then
		DPK_OPT["platform"]="test"
	else
		echo "$HOSTNAME" | grep -Eq "^server[0-9]*$|^serv[0-9]*$|^prod[0-9]*$|^web[0-9]*$|^db[0-9]*$|^cron[0-9]*$|^worker[0-9]*$|^front[0-9]*$|^back[0-9]*$"
		if [ $? -eq 0 ]; then
			DPK_OPT["platform"]="prod"
		else
			DPK_OPT["platform"]="dev"
		fi
	fi
	warn "$(ansi yellow)No platform given, $(ansi reset)${DPK_OPT["platform"]}$(ansi yellow) detected.$(ansi reset)"
}

# check_tag()
# Check if the tag given as a parameter already exists. Quit if not.
# If no tag is given, use the last created tag.
check_tag() {
	git_fetch
	if [ "${DPK_OPT["tag"]}" = "" ]; then
		_TAG=$(git tag | sort -V | tail -1)
		if [ "$_TAG" = "" ]; then
			abort "No tag found."
		fi
		DPK_OPT["tag"]=$_TAG
		echo "Using tag '$(ansi dim)${DPK_OPT["tag"]}$(ansi reset)'."
	elif [ "${DPK_OPT["tag"]}" != "$CONF_GIT_MAIN" ]; then
		FOUND=$(git tag | grep "^${DPK_OPT["tag"]}$" | wc -l)
		if [ $FOUND -eq 0 ]; then
			abort "$(ansi red)Bad value for 'tag' parameter (not an existing tag).$(ansi reset)"
		fi
	fi
}

# check_next_tag()
# Ask for the next tag number.
check_next_tag() {
	git_fetch
	LAST_TAG=$(git tag | sort -V | tail -1)
	# no existing tag
	if [ "$LAST_TAG" = "" ]; then
		if [ "${DPK_OPT["tag"]}" = "1.0.0" ] || [ "${DPK_OPT["tag"]}" = "0.1.0" ] || [ "${DPK_OPT["tag"]}" = "0.0.1" ]; then
			echo "Tag '$(ansi dim)${DPK_OPT["tag"]}$(ansi reset)' validated."
			return
		fi
		echo "$(ansi yellow)No existing tag.$(ansi reset)"
		echo "$(ansi bold)What is the number of the new version?$(ansi reset)"
		echo " A. 0.0.1 $(ansi dim)(first $(ansi yellow)pre-alpha$(ansi reset)$(ansi dim) version)$(ansi reset)"
		echo " B. 0.1.0 $(ansi dim)(first $(ansi yellow)alpha$(ansi reset)$(ansi dim) version)$(ansi reset)"
		echo " C. 1.0.0 $(ansi dim)(first major version)$(ansi reset)"
		read -p "[A] " ANSWER
		if [ "$ANSWER" = "1.0.0" ] || [ "$ANSWER" = "0.1.0" ] || [ "$ANSWER" = "0.0.1" ]; then
			DPK_OPT["tag"]="$ANSWER"
		elif [ "$ANSWER" = "" ] || [ "$ANSWER" = "a" ] || [ "$ANSWER" = "A" ]; then
			DPK_OPT["tag"]="0.0.1"
		elif [ "$ANSWER" = "b" ] || [ "$ANSWER" = "B" ]; then
			DPK_OPT["tag"]="0.1.0"
		elif [ "$ANSWER" = "c" ] || [ "$ANSWER" = "C" ]; then
			DPK_OPT["tag"]="1.0.0"
		else
			abort "$(ansi red)Bad choice.$(ansi reset)"
		fi
		return
	fi
	# some tags already exist
	LAST_MAJOR=$(echo "$LAST_TAG" | cut -d"." -f1)
	LAST_MINOR=$(echo "$LAST_TAG" | cut -d"." -f2)
	LAST_REVISION=$(echo "$LAST_TAG" | cut -d"." -f3)
	NEXT_MAJOR="$(($LAST_MAJOR + 1)).0.0"
	NEXT_REVISION="$LAST_MAJOR.$LAST_MINOR.$(($LAST_REVISION + 1))"
	if [ "$(($LAST_MINOR % 2))" = "0" ]; then
		# odd: stable version
		VERSION_TYPE="stable"
		NEXT_MINOR_UNSTABLE="$LAST_MAJOR.$(($LAST_MINOR + 1)).0"
		NEXT_MINOR_STABLE="$LAST_MAJOR.$(($LAST_MINOR + 2)).0"
	else
		# even: unstable version
		VERSION_TYPE="unstable"
		NEXT_MINOR_STABLE="$LAST_MAJOR.$(($LAST_MINOR + 1)).0"
		NEXT_MINOR_UNSTABLE="$LAST_MAJOR.$(($LAST_MINOR + 2)).0"
	fi
	# if a tag number was given, check if it's valid
	if [ "${DPK_OPT["tag"]}" = "$NEXT_MAJOR" ] || [ "${DPK_OPT["tag"]}" = "$NEXT_MINOR_STABLE" ] || [ "${DPK_OPT["tag"]}" = "$NEXT_MINOR_UNSTABLE" ] || [ "${DPK_OPT["tag"]}" = "$NEXT_REVISION" ]; then
		echo "Tag '$(ansi dim)${DPK_OPT["tag"]}$(ansi reset)' validated."
		return
	fi
	# no valid version number given, ask the user
	echo -n "Last version number: $(ansi dim)$LAST_TAG$(ansi reset) "
	if [ "$LAST_MAJOR" = "0" ] && [ "$LAST_MINOR" = "0" ]; then
		echo "($(ansi red)pre-alpha$(ansi reset))"
	elif [ "$LAST_MAJOR" = "0" ]; then
		if [ "$VERSION_TYPE" = "stable" ]; then
			echo "($(ansi green)stable $(ansi red)alpha$(ansi reset))"
		else
			echo "($(ansi yellow)unstable $(ansi red)alpha$(ansi reset))"
		fi
	elif [ "$VERSION_TYPE" = "stable" ]; then
		echo "($(ansi green)stable$(ansi reset))"
	else
		echo "($(ansi yellow)unstable$(ansi reset))"
	fi
	echo
	echo "$(ansi bold)What is the number of the new version?$(ansi reset)"
	if [ "$LAST_MAJOR" = "0" ] && [ "$LAST_MINOR" = "0" ]; then
		echo " A. $NEXT_REVISION $(ansi dim)(new $(ansi red)pre-alpha$(ansi reset)$(ansi dim) revision)$(ansi reset)"
	else
		echo " A. $NEXT_REVISION $(ansi dim)(new revision)$(ansi reset)"
	fi
	if [ "$VERSION_TYPE" = "stable" ]; then
		echo " B. $NEXT_MINOR_UNSTABLE $(ansi dim)(new $(ansi yellow)unstable$(ansi reset)$(ansi dim) minor version)$(ansi reset)"
		echo " C. $NEXT_MINOR_STABLE $(ansi dim)(new $(ansi green)stable$(ansi reset)$(ansi dim) minor version)$(ansi reset)"
	else
		echo " B. $NEXT_MINOR_STABLE $(ansi dim)(new $(ansi green)stable$(ansi reset)$(ansi dim) minor version)$(ansi reset)"
		echo " C. $NEXT_MINOR_UNSTABLE $(ansi dim)(new $(ansi yellow)unstable$(ansi reset)$(ansi dim) minor version)$(ansi reset)"
	fi
	echo " D. $NEXT_MAJOR $(ansi dim)(new major version)$(ansi reset)"
	read -p "[A] " ANSWER
	if [ "$ANSWER" = "$NEXT_MAJOR" ] || [ "$ANSWER" = "$NEXT_MINOR_STABLE" ] || [ "$ANSWER" = "$NEXT_MINOR_UNSTABLE" ] || [ "$ANSWER" = "$NEXT_REVISION" ]; then
		DPK_OPT["tag"]="$ANSWER"
	elif [ "$ANSWER" = "" ] || [ "$ANSWER" = "a" ] || [ "$ANSWER" = "A" ]; then
		DPK_OPT["tag"]="$NEXT_REVISION"
	elif [ "$ANSWER" = "b" ] || [ "$ANSWER" = "B" ]; then
		if [ "$VERSION_TYPE" = "stable" ]; then
			DPK_OPT["tag"]="$NEXT_MINOR_UNSTABLE"
		else
			DPK_OPT["tag"]="$NEXT_MINOR_STABLE"
		fi
	elif [ "$ANSWER" = "c" ] || [ "$ANSWER" = "C" ]; then
		if [ "$VERSION_TYPE" = "stable" ]; then
			DPK_OPT["tag"]="$NEXT_MINOR_STABLE"
		else
			DPK_OPT["tag"]="$NEXT_MINOR_UNSTABLE"
		fi
	elif [ "$ANSWER" = "d" ] || [ "$ANSWER" = "D" ]; then
		DPK_OPT["tag"]="$NEXT_MAJOR"
	else
		abort "$(ansi red)Bad choice.$(ansi reset)"
	fi
}


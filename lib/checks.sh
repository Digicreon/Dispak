#!/bin/bash

# check_aws()
# Check if the aws-cli program is installed.
check_aws() {
	which aws > /dev/null
	if [ $? -ne 0 ] ; then
		abort "$(ansi red)No 'aws' CLI program found.
   You need to install the AWS command-line tool to send file to Amazon S3.$(ansi reset)
     Installation:  $(ansi dim)\$ sudo apt-get install awscli$(ansi reset)
     Configuration: $(ansi dim)http://docs.aws.amazon.com/fr_fr/cli/latest/userguide/cli-chap-getting-started.html$(ansi reset)
     Usage:         $(ansi dim)http://docs.aws.amazon.com/fr_fr/cli/latest/userguide/cli-chap-using.html$(ansi reset)
  "
	fi
}

# check_dbhost()
# Check if the database host is defined.
check_dbhost() {
	if [ "$CONF_DB_HOST" = "" ]; then
		abort "Empty configuration for database host name."
	fi
	ping -c 1 db.skriv.tech > /dev/null
	if [ $? -ne 0 ]; then
		abort "$(ansi red)Unable to ping database hostname$(ansi reset) $DATABASE_HOSTNAME $(ansi red).$(ansi reset)"
	fi
}

# check_sudo()
# Check if the user has sudo rights.
check_sudo() {
	sudo echo "$(ansi green)✓ sudo rights checked$(ansi reset)" || exit 3
}

# check_url()
# Check if a configured URL responds correctly.
check_url() {
	if [ "$CONF_CHECK_URL" != "" ]; then
		if [ "$(curl -I -k "$CONF_CHECK_URL" 2> /dev/null | head -1 | cut -d' ' -f 2)" != "200" ]; then
			abort "$(ansi red)The URL $(ansi reset)$(ansi dim)$CONF_CHECK_URL$(ansi reset) $(ansi red)is returning an error.$(ansi reset)"
		fi
	fi
}

# check_git()
# Check if we are in a git repository. Abort if not.
check_git() {
	git rev-parse --is-inside-work-tree > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		abort "$(ansi red)The command $(ansi reset)$COMMAND$(ansi red) must be executed inside a git repository.$(ansi reset)"
	fi
}

# check_platform()
# Check if the platform given as a parameter is correct. Quit if not.
check_platform() {
	if [ "${DPK_OPTIONS["platform"]}" != "dev" ] && [ "${DPK_OPTIONS["platform"]}" != "test" ] && [ "${DPK_OPTIONS["platform"]}" != "prod" ]; then
		if [ "$CONF_PLATFORM" = "dev" ] || [ "$CONF_PLATFORM" = "test" ] || [ "$CONF_PLATFORM" = "prod" ]; then
			DPK_OPTIONS["platform"]=$CONF_PLATFORM
		else
			HOSTNAME=$(hostname)
			echo "$HOSTNAME" | grep -Eq "^test[0-9]+$"
			if [ $? -eq 0 ]; then
				DPK_OPTIONS["platform"]="test"
			else
				echo "$HOSTNAME" | grep -Eq "^prod[0-9]+$|^web[0-9]+$|^db[0-9]+$|^cron[0-9]+$|^worker[0-9]+$|^front[0-9]+$|^back[0-9]+$"
				if [ $? -eq 0 ]; then
					DPK_OPTIONS["platform"]="prod"
				else
					DPK_OPTIONS["platform"]="dev"
				fi
			fi
			warn "$(ansi yellow)No platform given, $(ansi reset)$PLATFORM$(ansi yellow) detected.$(ansi reset)"
		fi
	fi
}

# check_tag()
# Check if the tag given as a parameter already exists. Quit if not.
# If no tag is given, use the last created tag.
check_tag() {
	echo "$(ansi bold)Fetching new tags and branches$(ansi reset)"
	git fetch --all --tags --prune --quiet
	if [ "${DPK_OPTIONS["tag"]}" = "" ]; then
		DPK_OPTIONS["tag"]=$(git tag | sort -V | tail -1)
		echo "Using tag '$(ansi dim)${DPK_OPTIONS["tag"]}$(ansi reset)'."
	elif [ "${DPK_OPTIONS["tag"]}" = "master" ]; then
		DPK_OPTIONS["tag"]="master"
	else
		FOUND=$(git tag | grep "^${DPK_OPTIONS["tag"]}$" | wc -l)
		if [ $FOUND -eq 0 ]; then
			abort "$(ansi red)Bad value for 'tag' parameter (not an existing tag).$(ansi reset)"
		fi
	fi
}

# check_next_tag()
# Ask for the next tag number.
check_next_tag() {
	echo "$$(tput bold)Fetching new tags and branches$$(ansi reset)"
	git fetch --all --tags --prune --quiet
	LAST_TAG=$(git tag | sort -V | tail -1)
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
	if [ "${DPK_OPTIONS["tag"]}" = "$NEXT_MAJOR" ] || [ "${DPK_OPTIONS["tag"]}" = "$NEXT_MINOR_STABLE" ] || [ "${DPK_OPTIONS["tag"]}" = "$NEXT_MINOR_UNSTABLE" ] || [ "${DPK_OPTIONS["tag"]}" = "$NEXT_REVISION" ]; then
		echo "Tag '$(ansi dim)${DPK_OPTIONS["tag"]}$(ansi reset)' validated."
	else
		echo -n "Last version number: $(ansi dim)$LAST_TAG$(ansi reset) "
		if [ "$VERSION_TYPE" = "stable" ]; then
			echo "($(ansi green)stable$(ansi rerset))"
		else
			echo "($(ansi yellow)unstable$(ansi reset))"
		fi
		echo
		echo "$(ansi bold)What is the number of the new version?$(ansi reset)"
		echo " A. $NEXT_REVISION $(ansi dim)(new revision)$(ansi reset)"
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
			DPK_OPTIONS["tag"]="$ANSWER"
		elif [ "$ANSWER" = "" ] || [ "$ANSWER" = "a" ] || [ "$ANSWER" = "A" ]; then
			DPK_OPTIONS["tag"]="$NEXT_REVISION"
		elif [ "$ANSWER" = "b" ] || [ "$ANSWER" = "B" ]; then
			if [ "$VERSION_TYPE" = "stable" ]; then
				DPK_OPTIONS["tag"]="$NEXT_MINOR_UNSTABLE"
			else
				DPK_OPTIONS["tag"]="$NEXT_MINOR_STABLE"
			fi
		elif [ "$ANSWER" = "c" ] || [ "$ANSWER" = "C" ]; then
			if [ "$VERSION_TYPE" = "stable" ]; then
				DPK_OPTIONS["tag"]="$NEXT_MINOR_STABLE"
			else
				DPK_OPTIONS["tag"]="$NEXT_MINOR_UNSTABLE"
			fi
		elif [ "$ANSWER" = "d" ] || [ "$ANSWER" = "D" ]; then
			DPK_OPTIONS["tag"]="$NEXT_MAJOR"
		else
			abort "$(ansi red)Bad choice.$(ansi reset)"
		fi
	fi
}


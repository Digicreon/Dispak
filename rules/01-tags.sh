#!/bin/bash

# "tags" rule for Dispak
# © 2017, Amaury Bouchard <amaury@amaury.net>

# Rule's name.
RULE_NAME="tags"

# Rule's section (for documentation).
RULE_SECTION="Tag management"

# Rule's mandatory parameters.
RULE_MANDATORY_PARAMS=""

# Rule's optional parameters.
RULE_OPTIONAL_PARAMS="all"

# Show help for this rule.
rule_help_tags() {
	echo "   dpk $(ansi bold)tags$(ansi reset) $(ansi dim)[$(ansi reset)--all$(ansi dim)]$(ansi reset)"
	echo "       $(ansi dim)List all existing tags.$(ansi reset)"
	echo "       --all $(ansi dim) Display in-between revisions and tag annotations.$(ansi reset)"
}

# Execution of the rule
rule_exec_tags() {
	check_git
	LAST_MAJOR=""
	LAST_MINOR=""
	FIRST_REVISION=""
	LAST_REVISION=""
	LAST_DATE=""
	SHOWN="no"
	TAGS=$(git tag | sort -V)
	if [ "$TAGS" = "" ]; then
		abort "$(ansi red)No tag.$(ansi reset)"
	fi
	for TAG in $TAGS; do
		TAG_DATE=`git log -1 --format=%ai $TAG`
		TAG_MAJOR=`echo "$TAG" | cut -d"." -f1`
		TAG_MINOR=`echo "$TAG" | cut -d"." -f2`
		TAG_REVISION=`echo "$TAG" | cut -d"." -f3`
		# show last revision
		SHOWN="no"
		if [ "$LAST_MAJOR" != "$TAG_MAJOR" ] || [ "$LAST_MINOR" != "$TAG_MINOR" ]; then
			if [ "$FIRST_REVISION" != "$LAST_REVISION" ] && [ "$LAST_REVISION" != "" ]; then
				LEN=$((${#LAST_MAJOR} + ${#LAST_MINOR} + 1))
				SPACES=`printf "%0.s " $(seq 1 $LEN)`
				echo " $(ansi dim)$SPACES.$LAST_REVISION		$(ansi blue)$LAST_DATE$(ansi reset)"
				SHOWN="yes"
			fi
			LAST_MAJOR="$TAG_MAJOR"
			LAST_MINOR="$TAG_MINOR"
			FIRST_REVISION=""
			LAST_REVISION=""
		fi
		if [ "$TAG_MINOR" = "0" ] && [ "$TAG_REVISION" = "0" ]; then
			echo " $(ansi red)$(ansi bold)$TAG_MAJOR.0.0$(ansi reset)		$(ansi blue)$TAG_DATE$(ansi reset) $(ansi dim)major stable$(ansi reset)"
			SHOWN="yes"
			LAST_MAJOR=""
			LAST_MINOR=""
			FIRST_REVISION=""
			LAST_REVISION=""
		elif [ "$TAG_REVISION" = "0" ]; then
			if [ "$(($TAG_MINOR % 2))" = "0" ]; then
				echo " $(ansi green)$TAG_MAJOR.$TAG_MINOR.0		$(ansi blue)$TAG_DATE$(ansi reset) $(ansi green)$(ansi dim)stable$(ansi reset)"
			else
				echo " $(ansi yellow)$TAG_MAJOR.$TAG_MINOR.0		$(ansi blue)$TAG_DATE$(ansi reset) $(ansi yellow)$(ansi dim)unstable$(ansi reset)"
			fi
			SHOWN="yes"
			LAST_MAJOR=""
			LAST_MINOR=""
			FIRST_REVISION=""
			LAST_REVISION=""
		else
			if [ "${DPK_OPT["all"]}" != "" ] || [ "$FIRST_REVISION" = "" ]; then
				FIRST_REVISION="$TAG_REVISION"
			fi
			if [ "${DPK_OPT["all"]}" != "" ]; then
				echo " $(ansi dim)$TAG_MAJOR.$TAG_MINOR.$TAG_REVISION		$(ansi blue)$TAG_DATE$(ansi reset)"
				SHOWN="yes"
			fi
			LAST_REVISION="$TAG_REVISION"
		fi
		# show tag's annotation if needed
		if [ "$SHOWN" = "yes" ] && [ "${DPK_OPT["all"]}" != "" ]; then
			TAGGER="$(git tag -n --format='%(tagger)' $TAG | cut -d'>' -f 1)>"
			if [ "$(echo "$TAGGER" | grep "@" | wc -l)" == "1" ]; then
				echo "		$(ansi dim)$TAGGER$(ansi reset)"
			fi
			git tag -n99 $TAG | sed -e "s/^$TAG//" -e 's/^\s*//' | while read -r LINE; do
				echo "		$(ansi dim)$LINE$(ansi reset)"
			done
			echo
		fi
		LAST_DATE="$TAG_DATE"
	done
	if [ "${DPK_OPT["all"]}" = "" ] && [ "$SHOWN" = "no" ]; then
		LEN=$((${#LAST_MAJOR} + ${#LAST_MINOR} + 1))
		SPACES=`printf "%0.s " $(seq 1 $LEN)`
		echo " $(ansi dim)$SPACES.$LAST_REVISION		$(ansi blue)$TAG_DATE$(ansi reset)"
	fi
	NBR_COMMITS=$(git describe --long | cut -d"-" -f 2)
	echo
	if [ $NBR_COMMITS -eq 0 ]; then
		echo "No commit since last tag."
	elif [ $NBR_COMMITS -eq 1 ]; then
		echo "1 commit since last tag."
	else
		echo "$NBR_COMMITS commits since last tag."
	fi
}

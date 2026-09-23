#!/usr/bin/env bash

# Tests of the verbose mode (-v and --verbose options): the lines written by the dpk_echo()
# function are prefixed with the date and time, the next lines of a multi-line text are
# aligned with the first one, and empty texts are written without prefix. The rules' help
# is never prefixed.

. "$(dirname "$0")/lib.sh"

# load the real library, without ANSI decoration
. "$(dirname "$DPK")/lib/utils.sh"
ansi() { :; }

# regular expression of the date and time prefix
PREFIX_RE='\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] '
# indentation of the next lines of a multi-line text (22 spaces)
INDENT="                      "

echo "== normal mode =="
OPT_VERBOSE=0
OUT="$(dpk_echo "some text")"
[ "$OUT" = "some text" ]
check $? "text written as is"
OUT="$(dpk_echo "line 1
line 2")"
[ "$OUT" = "line 1
line 2" ]
check $? "multi-line text written as is"
OUT="$(dpk_echo -n "begin "; dpk_echo "end")"
[ "$OUT" = "begin end" ]
check $? "'-n' option: no trailing newline"

echo "== verbose mode =="
OPT_VERBOSE=1
OUT="$(dpk_echo "some text")"
[[ "$OUT" =~ ^${PREFIX_RE}some\ text$ ]]
check $? "text prefixed with the date and time, followed by a space"
[ "$(dpk_echo)" = "" ] && [ "$(dpk_echo "")" = "" ]
check $? "empty text written without prefix"
OUT="$(dpk_echo "line 1
line 2

line 4")"
[[ "$(echo "$OUT" | sed -n 1p)" =~ ^${PREFIX_RE}line\ 1$ ]]
check $? "multi-line text: first line prefixed"
[ "$(echo "$OUT" | sed -n 2p)" = "${INDENT}line 2" ] && [ "$(echo "$OUT" | sed -n 4p)" = "${INDENT}line 4" ]
check $? "multi-line text: next lines indented with 22 spaces"
[ "$(echo "$OUT" | sed -n 3p)" = "" ]
check $? "multi-line text: empty lines not indented"
OUT="$(dpk_echo -n "begin "; dpk_echo "end"; dpk_echo "next")"
[[ "$(echo "$OUT" | sed -n 1p)" =~ ^${PREFIX_RE}begin\ end$ ]] && [[ "$(echo "$OUT" | sed -n 2p)" =~ ^${PREFIX_RE}next$ ]]
check $? "'-n' option: the text continuing the line is not prefixed"
OUT="$(dpk_echo -n "begin "; dpk_echo; dpk_echo "next")"
[[ "$(echo "$OUT" | sed -n 2p)" =~ ^${PREFIX_RE}next$ ]]
check $? "'-n' option: an empty text ends the line"
OUT="$(dpk_echo_prefix)"
[[ "$OUT" =~ ^${PREFIX_RE}$ ]] && [ ${#OUT} -eq 22 ]
check $? "prefix is 22 characters long"
OPT_VERBOSE=0
[ "$(dpk_echo_prefix)" = "" ]
check $? "no prefix in normal mode"

echo "== command-line options =="
create_test_repos
git tag -a 0.1.0 -m "first version"
OUT="$(TERM= "$DPK" tags 2>&1)"
! echo "$OUT" | grep -Eq "$PREFIX_RE"
check $? "no prefix without the option"
OUT="$(TERM= "$DPK" tags -v 2>&1)"
[ $? -eq 0 ] && echo "$OUT" | grep -Eq "^${PREFIX_RE}No commit since last tag\.$"
check $? "'-v' option: lines prefixed"
OUT="$(TERM= "$DPK" tags --verbose --all 2>&1)"
[ $? -eq 0 ] && echo "$OUT" | grep -Eq "^${PREFIX_RE}.*0\.1\.0"
check $? "'--verbose' option: lines prefixed, other options still read"
OUT="$(TERM= "$DPK" tags --verbose 2>&1)"
[ "$(echo "$OUT" | grep -Ev "^${PREFIX_RE}" | grep -v "^$")" = "" ]
check $? "all the non-empty lines are prefixed"
OUT="$(TERM= "$DPK" nonexistentcommand -v 2>&1)"
[ $? -eq 11 ] && echo "$OUT" | grep -Eq "^${PREFIX_RE}.*Unknown command"
check $? "error messages prefixed"
OUT="$(TERM= "$DPK" help tags 2>&1)"
! echo "$OUT" | grep -Eq "$PREFIX_RE"
check $? "rule's help not prefixed"

test_end

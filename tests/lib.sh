#!/usr/bin/env bash

# Shared helpers for the Dispak test scripts.
# Each test script must source this file first:  . "$(dirname "$0")/lib.sh"

# Path to the tests directory and to the dpk executable.
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
DPK="$(dirname "$TESTS_DIR")/dpk"

# Tell if at least one assertion failed in the current test script.
FAILED=0

# check()
# Assert that the given status is 0, and display the result of the assertion.
# @param	int	Status to check (usually "$?").
# @param	string	Label of the assertion.
check() {
	if [ "$1" -eq 0 ]; then
		echo "  OK : $2"
	else
		echo "  KO : $2"
		FAILED=1
	fi
}

# test_end()
# Display the global result of the test script, and exit with the matching status.
test_end() {
	echo
	if [ $FAILED -eq 0 ]; then
		echo "=> PASS: $(basename "$0")"
	else
		echo "=> FAIL: $(basename "$0")"
	fi
	exit $FAILED
}

# create_test_dir()
# Create a temporary directory (removed when the script exits), set in $TEST_DIR.
create_test_dir() {
	TEST_DIR="$(mktemp -d /tmp/dispak-test.XXXXXXXX)"
	trap 'rm -rf "$TEST_DIR"' EXIT
}

# create_test_repos()
# Create a bare repository ($REMOTE) and two clones of it ($WORK and $WORK2) in a
# temporary directory. The repository contains the f1.txt to f4.txt files, committed
# on the main branch. The current directory is set to $WORK.
create_test_repos() {
	create_test_dir
	REMOTE="$TEST_DIR/remote.git"
	WORK="$TEST_DIR/work"
	WORK2="$TEST_DIR/work2"
	local I
	git init --bare -q "$REMOTE"
	git clone -q "$REMOTE" "$WORK" 2> /dev/null
	cd "$WORK"
	git config user.email test@test.com
	git config user.name Test
	for I in 1 2 3 4; do
		echo "content $I" > "f$I.txt"
	done
	git add .
	git commit -qm "init"
	git branch -m main 2> /dev/null
	git push -qu origin main
	git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
	git clone -q "$REMOTE" "$WORK2"
	git -C "$WORK2" config user.email test2@test.com
	git -C "$WORK2" config user.name Test2
}

# create_branch()
# Create a branch from the last revision of the main branch, with one committed and
# pushed change. The current branch is the new branch afterwards.
# @param	string	Name of the branch to create.
# @param	string	Name of the file to create or modify in the branch.
# @param	string	Content of the file.
create_branch() {
	git checkout -q main
	git checkout -qb "$1"
	echo "$3" > "$2"
	git add "$2"
	git commit -qm "change in $1"
	git push -qu origin "$1"
}

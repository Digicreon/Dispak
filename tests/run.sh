#!/usr/bin/env bash

# Run all the Dispak test scripts (tests/test-*.sh files).

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
GLOBAL_STATUS=0
for SCRIPT in "$TESTS_DIR"/test-*.sh; do
	echo "########## $(basename "$SCRIPT") ##########"
	if ! bash "$SCRIPT"; then
		GLOBAL_STATUS=1
	fi
	echo
done
if [ $GLOBAL_STATUS -eq 0 ]; then
	echo "ALL TESTS PASSED"
else
	echo "SOME TESTS FAILED"
fi
exit $GLOBAL_STATUS

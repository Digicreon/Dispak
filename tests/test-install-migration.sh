#!/usr/bin/env bash

# Tests of the database migration process of the 'dpk install' rule: nominal migration
# inside a transaction, automatic addition of the error storage column, failed migration
# (clear abort, exit code 42, no completion mark, error stored, new attempt at the next
# run), already applied statements (fatal by default, ignored with --force-migration
# unlike syntax errors), connection error (exit code 41), and degradation when the column can't be added.
# The real functions of the install rule are used, with a scriptable mysql stub which
# logs every received query and simulates the server state with files.

. "$(dirname "$0")/lib.sh"

# load the real library (DPK_EXIT_* codes and functions), then override with stubs
. "$(dirname "$DPK")/lib/utils.sh"
. "$(dirname "$DPK")/lib/checks.sh"
ansi() { :; }
warn() { echo "WARN: $1"; }
abort() { echo "ABORT: $1"; exit "${2:-1}"; }

# mysql stub: reads the queries on its standard input, logs them, and simulates a MySQL
# server which state is stored in $STATE_DIR files
mysql() {
	local QUERY VERSION LINE RET
	QUERY="$(cat)"
	printf 'ARGS: %s\n%s\n----\n' "$*" "$QUERY" >> "$STATE_DIR/queries.log"
	if [ -f "$STATE_DIR/down" ]; then
		echo "ERROR 2002 (HY000): Can't connect to MySQL server" >&2
		return 1
	fi
	case "$QUERY" in
		*"START TRANSACTION"*)
			# execution of a migration file (its content may contain any SQL keyword,
			# so this pattern must be checked first)
			# simulated errors are raised in the order of the file; without --force, the
			# execution stops at the first one
			RET=0
			while read -r LINE; do
				case "$LINE" in
					TRIGGER_SQL_ERROR*) echo "ERROR 1064 (42000) at line 2: You have an error in your SQL syntax" >&2 ;;
					TRIGGER_EXISTS_ERROR*) echo "ERROR 1050 (42S01) at line 2: Table 't2' already exists" >&2 ;;
					*) continue ;;
				esac
				RET=1
				[[ " $* " == *" --force "* ]] || return 1
			done <<< "$QUERY"
			return $RET
			;;
		*"SHOW COLUMNS"*)
			[ -f "$STATE_DIR/error-column" ] && echo "dbm_s_error"
			;;
		*"ADD COLUMN dbm_s_error"*)
			if [ -f "$STATE_DIR/alter-fails" ]; then
				echo "ERROR 1142 (42000): ALTER command denied" >&2
				return 1
			fi
			touch "$STATE_DIR/error-column"
			;;
		*"SELECT COUNT(*)"*)
			VERSION="$(echo "$QUERY" | sed "s/.*dbm_s_version = '\([^']*\)'.*/\1/")"
			if [ -f "$STATE_DIR/done" ]; then
				grep -c "^$VERSION$" "$STATE_DIR/done"
			else
				echo 0
			fi
			;;
		*"INSERT INTO"*)
			if [ -f "$STATE_DIR/insert-fails" ]; then
				echo "ERROR 1146 (42S02): Table doesn't exist" >&2
				return 1
			fi
			VERSION="$(echo "$QUERY" | sed "s/.*dbm_s_version = '\([^']*\)'.*/\1/")"
			echo "$VERSION" > "$STATE_DIR/last-version"
			echo "$(( $(cat "$STATE_DIR/counter" 2> /dev/null || echo 0) + 1 ))" > "$STATE_DIR/counter"
			cat "$STATE_DIR/counter"
			;;
		*"dbm_d_done = NOW()"*)
			cat "$STATE_DIR/last-version" >> "$STATE_DIR/done"
			;;
	esac
	return 0
}

# load the install rule, and create a fake repository with migration files
. "$(dirname "$DPK")/rules/03-install.sh"
create_test_dir
STATE_DIR="$TEST_DIR/state"
mkdir -p "$STATE_DIR"
GIT_REPO_PATH="$TEST_DIR/repo"
mkdir -p "$GIT_REPO_PATH/etc/database/migrations"
echo "CREATE TABLE IF NOT EXISTS t1 (id INT);" > "$GIT_REPO_PATH/etc/database/migrations/0.1.0"
echo "ALTER TABLE t1 ADD COLUMN c INT;" > "$GIT_REPO_PATH/etc/database/migrations/0.2.0"
touch "$GIT_REPO_PATH/etc/database/migrations/current"
CONF_GIT_MAIN="main"
CONF_DB_HOST="localhost"
CONF_DB_PORT="3306"
CONF_DB_USER="user"
CONF_DB_PWD="password"
CONF_DB_MIGRATION_BASE="base"
CONF_DB_MIGRATION_TABLE="migrations"
declare -A DPK_OPT

echo "== nominal migration =="
OUT="$(_install_db_migration 2>&1)"
check $? "the migration succeeds"
[ "$(grep -c "INSERT INTO" "$STATE_DIR/queries.log")" -eq 2 ] && [ "$(grep -c "^0\." "$STATE_DIR/done")" -eq 2 ]
check $? "both migration files executed and marked as done"
[ "$(grep -c "START TRANSACTION" "$STATE_DIR/queries.log")" -eq 2 ] && [ "$(grep -c "^COMMIT;$" "$STATE_DIR/queries.log")" -eq 2 ]
check $? "files executed inside transactions"
[ -f "$STATE_DIR/error-column" ] && [ "$(grep -c "ADD COLUMN dbm_s_error" "$STATE_DIR/queries.log")" -eq 1 ]
check $? "error storage column automatically added"

echo "== second run =="
OUT="$(_install_db_migration 2>&1)"
check $? "the command succeeds"
[ "$(grep -c "INSERT INTO" "$STATE_DIR/queries.log")" -eq 2 ]
check $? "already-done migrations skipped"
[ "$(grep -c "ADD COLUMN dbm_s_error" "$STATE_DIR/queries.log")" -eq 1 ]
check $? "existing error column detected (no new ALTER)"

echo "== failed migration =="
echo "TRIGGER_SQL_ERROR;" > "$GIT_REPO_PATH/etc/database/migrations/0.3.0"
OUT="$(_install_db_migration 2>&1)"
RET=$?
[ $RET -eq 42 ]
check $? "aborts with exit code 42"
echo "$OUT" | grep -q "ERROR 1064"
check $? "the MySQL error message is displayed"
echo "$OUT" | grep -q "will be executed again at the next install"
check $? "the abort message explains the retry behavior"
! grep -q "^0.3.0$" "$STATE_DIR/done"
check $? "the failed migration is not marked as done"
grep "dbm_s_error = " "$STATE_DIR/queries.log" | grep -q "ERROR 1064"
check $? "the error message is stored in the tracking row"

echo "== new attempt at the next run =="
OUT="$(_install_db_migration 2>&1)"
RET=$?
[ $RET -eq 42 ]
check $? "the failed migration is tried again (exit code 42)"
[ "$(grep "INSERT INTO" "$STATE_DIR/queries.log" | grep -c "0.3.0")" -eq 2 ]
check $? "a new tracking row is created for the new attempt"

echo "== already applied statement, without --force-migration =="
rm -f "$GIT_REPO_PATH/etc/database/migrations/0.3.0"
printf 'TRIGGER_EXISTS_ERROR;\nINSERT INTO t2 VALUES (1);\n' > "$GIT_REPO_PATH/etc/database/migrations/0.4.0"
OUT="$(_install_db_migration 2>&1)"
RET=$?
[ $RET -eq 42 ] && echo "$OUT" | grep -q "ERROR 1050"
check $? "aborts with exit code 42 (default behavior unchanged)"
! grep -q -- "^ARGS: .*--force" "$STATE_DIR/queries.log"
check $? "the mysql client is not called with --force"

echo "== already applied statement, with --force-migration =="
DPK_OPT["force-migration"]=""
OUT="$(_install_db_migration 2>&1)"
check $? "the migration succeeds"
grep -q "^0.4.0$" "$STATE_DIR/done"
check $? "the migration is marked as done"
grep -q -- "^ARGS: --force " "$STATE_DIR/queries.log"
check $? "the mysql client is called with --force"

echo "== syntax error, with --force-migration =="
printf 'TRIGGER_EXISTS_ERROR;\nTRIGGER_SQL_ERROR;\n' > "$GIT_REPO_PATH/etc/database/migrations/0.5.0"
OUT="$(_install_db_migration 2>&1)"
RET=$?
[ $RET -eq 42 ]
check $? "aborts with exit code 42"
echo "$OUT" | grep -q "ERROR 1064"
check $? "the syntax error is displayed"
! grep -q "^0.5.0$" "$STATE_DIR/done"
check $? "the failed migration is not marked as done"
rm -f "$GIT_REPO_PATH/etc/database/migrations/0.4.0" "$GIT_REPO_PATH/etc/database/migrations/0.5.0"
unset 'DPK_OPT[force-migration]'

echo "== connection error =="
touch "$STATE_DIR/down"
OUT="$(_install_db_migration 2>&1)"
RET=$?
[ $RET -eq 41 ]
check $? "aborts with exit code 41 when the connection fails"
rm -f "$STATE_DIR/down"

echo "== degradation when the error column can't be added =="
rm -f "$GIT_REPO_PATH/etc/database/migrations/0.3.0"
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/alter-fails"
OUT="$(_install_db_migration 2>&1)"
check $? "the migration still succeeds"
echo "$OUT" | grep -q "WARN"
check $? "a warning is displayed"

echo "== tracking failure =="
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/error-column"
touch "$STATE_DIR/insert-fails"
OUT="$(_install_db_migration 2>&1)"
RET=$?
[ $RET -eq 43 ]
check $? "aborts with exit code 43 when the tracking row can't be created"

test_end

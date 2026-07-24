#!/usr/bin/env bash

# Tests of the 'dpk install' rule functions: the --no-* options (an option given without
# a value must be detected and disable the corresponding installation step), and the
# version alias links management. The real functions of the install rule are used, with
# stubbed system commands (no system command is really executed).

. "$(dirname "$0")/lib.sh"

# stubs (no system command is really executed)
declare -A DPK_OPT
ansi() { :; }
abort() { echo "ABORT: $*"; exit 1; }
warn() { echo "WARN: $*"; }
crontab() { echo "[stub crontab $*]"; }
sudo() { echo "[stub sudo $*]"; }
mysql() { echo "[stub mysql $*]"; }

# load the install rule, and create a fake repository
. "$(dirname "$DPK")/rules/03-install.sh"
create_test_dir
GIT_REPO_PATH="$TEST_DIR/repo"
CONF_GIT_MAIN="main"
mkdir -p "$GIT_REPO_PATH/etc"

echo "== --no-crontab =="
echo "0 0 * * * true" > "$GIT_REPO_PATH/etc/crontab"
DPK_OPT=()
DPK_OPT["no-crontab"]=""
OUT="$(_install_crontab)"
[ -z "$OUT" ]
check $? "without a value: crontab installation skipped"
DPK_OPT=()
DPK_OPT["no-crontab"]="1"
OUT="$(_install_crontab)"
[ -z "$OUT" ]
check $? "with a value: crontab installation skipped"
DPK_OPT=()
OUT="$(_install_crontab)"
echo "$OUT" | grep -q "stub crontab"
check $? "without the option: crontab installation performed"

echo "== --no-xinetd =="
echo "service dispak {}" > "$GIT_REPO_PATH/etc/xinetd"
DPK_OPT=()
DPK_OPT["no-xinetd"]=""
OUT="$(_install_xinetd)"
[ -z "$OUT" ]
check $? "xinetd installation skipped"
DPK_OPT=()
OUT="$(_install_xinetd)"
echo "$OUT" | grep -q "Installing xinetd"
check $? "without the option: xinetd installation performed"

echo "== --no-supervisor =="
mkdir -p "$GIT_REPO_PATH/etc/supervisor"
echo "[program:x]" > "$GIT_REPO_PATH/etc/supervisor/x.conf"
DPK_OPT=()
DPK_OPT["no-supervisor"]=""
OUT="$(_install_supervisor)"
[ -z "$OUT" ]
check $? "supervisor installation skipped"
DPK_OPT=()
OUT="$(_install_supervisor)"
echo "$OUT" | grep -q "Installing Supervisor"
check $? "without the option: supervisor installation performed"

echo "== --no-systemd =="
mkdir -p "$GIT_REPO_PATH/etc/systemd"
echo "[Unit]" > "$GIT_REPO_PATH/etc/systemd/x.service"
DPK_OPT=()
DPK_OPT["no-systemd"]=""
OUT="$(_install_systemd)"
[ -z "$OUT" ]
check $? "systemd installation skipped"
DPK_OPT=()
OUT="$(_install_systemd)"
echo "$OUT" | grep -q "Installing systemd"
check $? "without the option: systemd installation performed"

echo "== --no-apache =="
# (only the option's guard is tested: the counter-test would depend on the presence
# of the /etc/apache2 directory on the machine running the tests)
CONF_INSTALL_APACHE_FILES="$GIT_REPO_PATH/etc/apache.conf"
DPK_OPT=()
DPK_OPT["no-apache"]=""
OUT="$(_install_config_apache)"
[ -z "$OUT" ]
check $? "apache installation skipped"
CONF_INSTALL_APACHE_FILES=""

echo "== --no-db-migration =="
mkdir -p "$GIT_REPO_PATH/etc/database/migrations"
echo "ALTER TABLE x;" > "$GIT_REPO_PATH/etc/database/migrations/1.0.0"
CONF_DB_HOST="localhost"
CONF_DB_PORT="3306"
CONF_DB_USER="user"
CONF_DB_PWD="password"
CONF_DB_MIGRATION_BASE="base"
CONF_DB_MIGRATION_TABLE="migrations"
DPK_OPT=()
DPK_OPT["no-db-migration"]=""
OUT="$(_install_db_migration)"
[ -z "$OUT" ]
check $? "database migration skipped"
DPK_OPT=()
OUT="$(_install_db_migration)"
echo "$OUT" | grep -q "Database migration"
check $? "without the option: database migration performed"

echo "== version alias links =="
cd "$GIT_REPO_PATH"
mkdir -p www/css www/js
echo "css content" > www/css/style.css
CONF_INSTALL_VERSION_ALIAS="www/css/style.css www/js"
DPK_OPT=()
DPK_OPT["tag"]="1.2.0"
_install_version_alias > /dev/null
[ -L www/css/style-1.2.0.css ] && [ "$(readlink www/css/style-1.2.0.css)" = "style.css" ]
check $? "file alias created (version before the extension)"
[ -L www/js-1.2.0 ] && [ "$(readlink www/js-1.2.0)" = "js" ]
check $? "directory alias created (version at the end of the name)"
ln -s js www/js-custom
_install_version_alias_cleanup > /dev/null
[ ! -L www/css/style-1.2.0.css ] && [ ! -L www/js-1.2.0 ]
check $? "version alias links removed by the cleanup"
[ -L www/js-custom ]
check $? "non-version links preserved by the cleanup"

test_end

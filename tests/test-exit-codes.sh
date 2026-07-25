#!/usr/bin/env bash

# Unit tests of the exit codes that can't be triggered end-to-end (they would need sudo
# rights, or a specific machine state). The real check and rule functions are used, with
# stubbed system commands.

. "$(dirname "$0")/lib.sh"

# load the real library (DPK_EXIT_* codes and functions), then override with stubs
. "$(dirname "$DPK")/lib/utils.sh"
. "$(dirname "$DPK")/lib/checks.sh"
. "$(dirname "$DPK")/rules/02-pkg.sh"
. "$(dirname "$DPK")/rules/03-install.sh"
. "$(dirname "$DPK")/rules/04-config.sh"
ansi() { :; }
warn() { echo "WARN: $1"; }
abort() { echo "ABORT: $1"; exit "${2:-1}"; }

create_test_dir
GIT_REPO_PATH="$TEST_DIR/repo"
mkdir -p "$GIT_REPO_PATH/etc"
declare -A DPK_OPT
# failing user script, given as pre/post script of the rules
FAIL_SCRIPT="$TEST_DIR/fail.sh"
printf '#!/bin/sh\nexit 1\n' > "$FAIL_SCRIPT"
chmod +x "$FAIL_SCRIPT"

echo "== sudo error =="
sudo() { return 1; }
( check_sudo ) > /dev/null 2>&1
[ $? -eq 3 ]
check $? "sudo rights error (exit code 3)"

echo "== missing program =="
which() { return 1; }
CONF_PKG_MINIFY["a.min.js"]="a.js"
( _pkg_check_minify ) > /dev/null 2>&1
[ $? -eq 21 ]
check $? "missing minifier program (exit code 21)"
CONF_PKG_MINIFY=()
unset -f which

echo "== failing user scripts =="
CONF_CONFIG_SCRIPTS_PRE="$FAIL_SCRIPT"
( _config_pre_scripts ) > /dev/null 2>&1
[ $? -eq 53 ]
check $? "pre-configuration script failure (exit code 53)"
CONF_CONFIG_SCRIPTS_PRE=""
CONF_CONFIG_SCRIPTS_POST="$FAIL_SCRIPT"
( _config_post_scripts ) > /dev/null 2>&1
[ $? -eq 54 ]
check $? "post-configuration script failure (exit code 54)"
CONF_CONFIG_SCRIPTS_POST=""
CONF_INSTALL_SCRIPTS_PRE="$FAIL_SCRIPT"
( _install_pre_scripts ) > /dev/null 2>&1
[ $? -eq 55 ]
check $? "pre-install script failure (exit code 55)"
CONF_INSTALL_SCRIPTS_PRE=""
CONF_INSTALL_SCRIPTS_POST="$FAIL_SCRIPT"
( _install_post_scripts ) > /dev/null 2>&1
[ $? -eq 56 ]
check $? "post-install script failure (exit code 56)"
CONF_INSTALL_SCRIPTS_POST=""

echo "== failing generator script =="
crontab() { :; }
printf '#!/bin/sh\nexit 1\n' > "$GIT_REPO_PATH/etc/crontab.gen"
chmod +x "$GIT_REPO_PATH/etc/crontab.gen"
( _install_crontab ) > /dev/null 2>&1
[ $? -eq 57 ]
check $? "generator script failure (exit code 57)"

test_end

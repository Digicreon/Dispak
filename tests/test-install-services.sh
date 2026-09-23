#!/usr/bin/env bash

# Tests of the system services configuration installed by the 'dpk install' rule (systemd,
# Supervisor, xinetd, crontab): ownership markers, removal of the configuration installed
# by previous deployments when its source disappears from the repository, empty and failing
# generators. The real functions of the install rule are used, with the system paths
# redirected to a temporary directory and stubbed service managers (no service is really
# touched).

. "$(dirname "$0")/lib.sh"

# stubs
declare -A DPK_OPT
ansi() { :; }
dpk_echo() { echo "$@"; }
abort() { echo "ABORT: $*"; exit 1; }
warn() { echo "WARN: $*"; }
sudo() { "$@"; }
systemctl() { echo "[stub systemctl $*]"; }
supervisorctl() { echo "[stub supervisorctl $*]"; }
# file-backed crontab (the new content is written in a separate file, so a reader of the
# current content is never truncated)
crontab() {
	if [ "$1" = "-l" ]; then
		cat "$CRONTAB_FILE" 2> /dev/null
	else
		cat > "$CRONTAB_FILE.new" && mv "$CRONTAB_FILE.new" "$CRONTAB_FILE"
	fi
}

# load the install rule, and create a fake repository and fake system directories
. "$(dirname "$DPK")/rules/03-install.sh"
create_test_dir
GIT_REPO_PATH="$TEST_DIR/repo"
CONF_GIT_MAIN="main"
DPK_SYSTEMD_DIR="$TEST_DIR/systemd"
DPK_SUPERVISOR_DIR="$TEST_DIR/supervisor"
DPK_XINETD_FILE="$TEST_DIR/xinetd.d/dispak"
CRONTAB_FILE="$TEST_DIR/crontab"
mkdir -p "$GIT_REPO_PATH/etc/systemd" "$GIT_REPO_PATH/etc/supervisor" "$DPK_SYSTEMD_DIR" "$DPK_SUPERVISOR_DIR" "$TEST_DIR/xinetd.d"
DPK_OPT=()
DPK_OPT["platform"]="test"
DPK_OPT["tag"]="1.0.0"

echo "== systemd: installation and cleanup =="
printf '[Unit]\nDescription=copied\n' > "$GIT_REPO_PATH/etc/systemd/copied.service"
printf '#!/usr/bin/env bash\necho "[Unit]"\necho "Description=generated for $1 $2"\n' > "$GIT_REPO_PATH/etc/systemd/generated.service.gen"
printf '#!/usr/bin/env bash\nexit 0\n' > "$GIT_REPO_PATH/etc/systemd/silent.service.gen"
# a unit installed by hand, and a unit installed by Dispak from another repository
printf '[Unit]\nDescription=manual\n' > "$DPK_SYSTEMD_DIR/manual.service"
{ _install_config_marker SYSTEMD "/other/repo/etc/systemd/other.service"; echo "[Unit]"; } > "$DPK_SYSTEMD_DIR/other.service"
# units installed by a previous deployment of this repository, whose sources disappeared
{ _install_config_marker SYSTEMD "$GIT_REPO_PATH/etc/systemd/old.service"; echo "[Unit]"; } > "$DPK_SYSTEMD_DIR/old.service"
{ _install_config_marker SYSTEMD "$GIT_REPO_PATH/etc/systemd/oldtarget.target.gen"; echo "[Unit]"; } > "$DPK_SYSTEMD_DIR/oldtarget.target"
{ _install_config_marker SYSTEMD "$GIT_REPO_PATH/etc/systemd/oldtarget@.service"; echo "[Unit]"; } > "$DPK_SYSTEMD_DIR/oldtarget@.service"
# a unit installed by a previous deployment, whose generator outputs nothing now
{ _install_config_marker SYSTEMD "$GIT_REPO_PATH/etc/systemd/silent.service.gen"; echo "[Unit]"; } > "$DPK_SYSTEMD_DIR/silent.service"
OUT="$(_install_systemd)"
[ "$(head -n 1 "$DPK_SYSTEMD_DIR/copied.service")" = "$(_install_config_marker SYSTEMD "$GIT_REPO_PATH/etc/systemd/copied.service")" ]
check $? "copied unit: marker with the source file's path"
grep -q "^Description=copied$" "$DPK_SYSTEMD_DIR/copied.service"
check $? "copied unit: content copied after the marker"
[ "$(head -n 1 "$DPK_SYSTEMD_DIR/generated.service")" = "$(_install_config_marker SYSTEMD "$GIT_REPO_PATH/etc/systemd/generated.service.gen")" ]
check $? "generated unit: marker with the generator's path"
grep -q "^Description=generated for test 1.0.0$" "$DPK_SYSTEMD_DIR/generated.service"
check $? "generated unit: generator output (with platform and tag)"
echo "$OUT" | grep -q "stub systemctl enable copied.service" && echo "$OUT" | grep -q "stub systemctl restart generated.service"
check $? "installed units enabled and started"
echo "$OUT" | grep -q "silent.service empty"
check $? "silent generator: reported as empty"
[ ! -e "$DPK_SYSTEMD_DIR/silent.service" ]
check $? "silent generator: previously installed unit removed"
echo "$OUT" | grep -q "stub systemctl stop silent.service" && echo "$OUT" | grep -q "stub systemctl disable silent.service"
check $? "silent generator: previously installed unit stopped and disabled"
[ ! -e "$DPK_SYSTEMD_DIR/old.service" ]
check $? "obsolete unit removed"
echo "$OUT" | grep -q "stub systemctl stop old.service" && echo "$OUT" | grep -q "stub systemctl disable old.service"
check $? "obsolete unit stopped and disabled"
[ ! -e "$DPK_SYSTEMD_DIR/oldtarget.target" ] && [ ! -e "$DPK_SYSTEMD_DIR/oldtarget@.service" ]
check $? "obsolete target and template unit removed"
echo "$OUT" | grep -q "stub systemctl stop oldtarget.target" && ! echo "$OUT" | grep -q "stub systemctl stop oldtarget@.service"
check $? "obsolete target stopped, template unit not stopped by itself"
[ -e "$DPK_SYSTEMD_DIR/manual.service" ] && [ -e "$DPK_SYSTEMD_DIR/other.service" ]
check $? "manually installed unit and other repository's unit preserved"
echo "$OUT" | grep -q "stub systemctl daemon-reload"
check $? "systemd configuration reloaded"

echo "== systemd: target =="
printf '#!/usr/bin/env bash\necho "[Unit]"\necho "Description=workers"\n' > "$GIT_REPO_PATH/etc/systemd/workers.target.gen"
printf '[Unit]\nDescription=worker %%i\n' > "$GIT_REPO_PATH/etc/systemd/workers@.service"
OUT="$(_install_systemd)"
[ -f "$DPK_SYSTEMD_DIR/workers.target" ] && [ -f "$DPK_SYSTEMD_DIR/workers@.service" ]
check $? "target and template unit installed"
[ "$(head -n 1 "$DPK_SYSTEMD_DIR/workers@.service")" = "$(_install_config_marker SYSTEMD "$GIT_REPO_PATH/etc/systemd/workers@.service")" ]
check $? "template unit: marker with the source file's path"
echo "$OUT" | grep -q "stub systemctl restart workers.target" && ! echo "$OUT" | grep -q "stub systemctl restart workers@.service"
check $? "target started, template unit not started by itself"
OUT="$(_install_systemd)"
! echo "$OUT" | grep -q "Removing"
check $? "second deployment: nothing removed"
# the template unit's generator outputs nothing now
rm "$GIT_REPO_PATH/etc/systemd/workers@.service"
printf '#!/usr/bin/env bash\nexit 0\n' > "$GIT_REPO_PATH/etc/systemd/workers@.service.gen"
OUT="$(_install_systemd)"
[ ! -e "$DPK_SYSTEMD_DIR/workers.target" ] && [ ! -e "$DPK_SYSTEMD_DIR/workers@.service" ]
check $? "silent template generator: target and template unit removed"
rm "$GIT_REPO_PATH/etc/systemd/workers.target.gen" "$GIT_REPO_PATH/etc/systemd/workers@.service.gen"
# plain target file, without template unit
printf '[Unit]\nDescription=alone\n' > "$GIT_REPO_PATH/etc/systemd/alone.target"
OUT="$(_install_systemd)"
echo "$OUT" | grep -q "ABORT: .*Unable to find file"
check $? "target without template unit: installation aborted"
rm "$GIT_REPO_PATH/etc/systemd/alone.target"

echo "== systemd: generator failure =="
printf '#!/usr/bin/env bash\nexit 3\n' > "$GIT_REPO_PATH/etc/systemd/broken.service.gen"
printf 'previous content\n' > "$DPK_SYSTEMD_DIR/broken.service"
OUT="$(_install_systemd)"
echo "$OUT" | grep -q "ABORT: .*execution failed"
check $? "installation aborted"
[ "$(cat "$DPK_SYSTEMD_DIR/broken.service")" = "previous content" ]
check $? "previously installed unit left untouched"
rm "$GIT_REPO_PATH/etc/systemd/broken.service.gen" "$DPK_SYSTEMD_DIR/broken.service"

echo "== systemd: directory removed from the repository =="
rm -rf "$GIT_REPO_PATH/etc/systemd"
OUT="$(_install_systemd)"
! echo "$OUT" | grep -q "Installing systemd"
check $? "no installation"
[ ! -e "$DPK_SYSTEMD_DIR/copied.service" ] && [ ! -e "$DPK_SYSTEMD_DIR/generated.service" ]
check $? "all the repository's units removed"
[ -e "$DPK_SYSTEMD_DIR/manual.service" ] && [ -e "$DPK_SYSTEMD_DIR/other.service" ]
check $? "other units preserved"
OUT="$(_install_systemd)"
[ -z "$OUT" ]
check $? "nothing to do: no output"

echo "== Supervisor =="
printf '[program:copied]\ncommand=/bin/true\n' > "$GIT_REPO_PATH/etc/supervisor/copied.conf"
printf '#!/usr/bin/env bash\necho "[program:generated]"\necho "command=/bin/true $1"\n' > "$GIT_REPO_PATH/etc/supervisor/generated.conf.gen"
printf '#!/usr/bin/env bash\nexit 0\n' > "$GIT_REPO_PATH/etc/supervisor/silent.conf.gen"
printf '[program:manual]\n' > "$DPK_SUPERVISOR_DIR/manual.conf"
{ _install_config_marker SUPERVISOR "/other/repo/etc/supervisor/other.conf"; echo "[program:other]"; } > "$DPK_SUPERVISOR_DIR/other.conf"
{ _install_config_marker SUPERVISOR "$GIT_REPO_PATH/etc/supervisor/old.conf"; echo "[program:old]"; } > "$DPK_SUPERVISOR_DIR/old.conf"
{ _install_config_marker SUPERVISOR "$GIT_REPO_PATH/etc/supervisor/silent.conf.gen"; echo "[program:silent]"; } > "$DPK_SUPERVISOR_DIR/silent.conf"
OUT="$(_install_supervisor)"
[ "$(head -n 1 "$DPK_SUPERVISOR_DIR/copied.conf")" = "$(_install_config_marker SUPERVISOR "$GIT_REPO_PATH/etc/supervisor/copied.conf")" ]
check $? "copied file: marker with the source file's path"
[ "$(head -n 1 "$DPK_SUPERVISOR_DIR/generated.conf")" = "$(_install_config_marker SUPERVISOR "$GIT_REPO_PATH/etc/supervisor/generated.conf.gen")" ]
check $? "generated file: marker with the generator's path"
grep -q "^command=/bin/true test$" "$DPK_SUPERVISOR_DIR/generated.conf"
check $? "generated file: generator output"
echo "$OUT" | grep -q "silent.conf empty" && [ ! -e "$DPK_SUPERVISOR_DIR/silent.conf" ]
check $? "silent generator: reported as empty, previously installed file removed"
[ ! -e "$DPK_SUPERVISOR_DIR/old.conf" ]
check $? "obsolete file removed"
[ -e "$DPK_SUPERVISOR_DIR/manual.conf" ] && [ -e "$DPK_SUPERVISOR_DIR/other.conf" ]
check $? "manually installed file and other repository's file preserved"
echo "$OUT" | grep -q "stub supervisorctl reread" && echo "$OUT" | grep -q "stub supervisorctl update"
check $? "Supervisor configuration reloaded"
rm -rf "$GIT_REPO_PATH/etc/supervisor"
OUT="$(_install_supervisor)"
[ ! -e "$DPK_SUPERVISOR_DIR/copied.conf" ] && [ ! -e "$DPK_SUPERVISOR_DIR/generated.conf" ] && [ -e "$DPK_SUPERVISOR_DIR/manual.conf" ]
check $? "directory removed from the repository: the repository's files removed, others preserved"
echo "$OUT" | grep -q "stub supervisorctl update"
check $? "directory removed from the repository: Supervisor configuration reloaded"
OUT="$(_install_supervisor)"
[ -z "$OUT" ]
check $? "nothing to do: no output"

echo "== xinetd =="
XSTART="# ┏━━━━━┥DISPAK XINETD START┝━━━┥$GIT_REPO_PATH/etc/xinetd┝━━━━━┓"
printf '# other project\n' > "$DPK_XINETD_FILE"
printf 'service one\n{\n\tport = 1\n}\n' > "$GIT_REPO_PATH/etc/xinetd"
OUT="$(_install_xinetd)"
grep -qxF -- "$XSTART" "$DPK_XINETD_FILE" && grep -qF "port = 1" "$DPK_XINETD_FILE"
check $? "block added"
echo "$OUT" | grep -q "stub systemctl reload xinetd"
check $? "xinetd reloaded after installation"
printf 'service two\n{\n\tport = 2\n}\n' > "$GIT_REPO_PATH/etc/xinetd"
_install_xinetd > /dev/null
grep -qF "port = 2" "$DPK_XINETD_FILE" && ! grep -qF "port = 1" "$DPK_XINETD_FILE"
check $? "block replaced"
[ "$(grep -cxF -- "$XSTART" "$DPK_XINETD_FILE")" = "1" ]
check $? "block replaced: single start marker"
rm "$GIT_REPO_PATH/etc/xinetd"
OUT="$(_install_xinetd)"
echo "$OUT" | grep -q "Removing xinetd"
check $? "file removed from the repository: removal reported"
! grep -qF "DISPAK XINETD" "$DPK_XINETD_FILE" && ! grep -qF "port = 2" "$DPK_XINETD_FILE"
check $? "block removed"
grep -qxF "# other project" "$DPK_XINETD_FILE"
check $? "other content preserved"
echo "$OUT" | grep -q "stub systemctl reload xinetd"
check $? "xinetd reloaded after removal"
OUT="$(_install_xinetd)"
[ -z "$OUT" ]
check $? "nothing to do: no output"

echo "== crontab =="
CSTART="# ┏━━━━━┥DISPAK CRONTAB START┝━━━┥$GIT_REPO_PATH/etc/crontab┝━━━━━┓"
printf '* * * * * local_command\n' > "$CRONTAB_FILE"
printf '0 0 * * * dispak_command\n' > "$GIT_REPO_PATH/etc/crontab"
_install_crontab > /dev/null
grep -qxF -- "$CSTART" "$CRONTAB_FILE" && grep -q "dispak_command$" "$CRONTAB_FILE"
check $? "block added"
printf '0 1 * * * dispak_command2\n' > "$GIT_REPO_PATH/etc/crontab"
_install_crontab > /dev/null
grep -q "dispak_command2$" "$CRONTAB_FILE" && ! grep -q "dispak_command$" "$CRONTAB_FILE"
check $? "block replaced"
[ "$(grep -cxF -- "$CSTART" "$CRONTAB_FILE")" = "1" ]
check $? "block replaced: single start marker"
rm "$GIT_REPO_PATH/etc/crontab"
OUT="$(_install_crontab)"
echo "$OUT" | grep -q "Removing crontab"
check $? "file removed from the repository: removal reported"
! grep -qF "DISPAK CRONTAB" "$CRONTAB_FILE" && ! grep -q "dispak_command" "$CRONTAB_FILE"
check $? "block removed"
grep -qxF "* * * * * local_command" "$CRONTAB_FILE"
check $? "other content preserved"
OUT="$(_install_crontab)"
[ -z "$OUT" ]
check $? "nothing to do: no output"

test_end

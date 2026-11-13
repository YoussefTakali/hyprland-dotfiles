#!/usr/bin/env bash
# Prepare one explicit native startup trial; never restart the running desktop.
set -euo pipefail
[[ $EUID != 0 ]] || { echo 'Run this as your normal desktop user.' >&2; exit 1; }
HERE=$(cd "$(dirname "$0")/../.." && pwd)
export REPO_FOR_TRIAL=$HERE
# A real desktop preflight is required; a sandbox must stop before root changes.
python3 - <<'PY'
import json,os,subprocess
from pathlib import Path
h=Path.home()
p=subprocess.run(['/usr/bin/hyprctl','-j','monitors'],capture_output=True,text=True,timeout=5)
if p.returncode:raise SystemExit('Desktop access required: '+(p.stderr or p.stdout).strip())
outputs=json.loads(p.stdout)
if len(outputs)!=1 or outputs[0]['scale']!=int(outputs[0]['scale']):
 raise SystemExit('This one-shot trial requires a single monitor with integer scaling.')
lua=h/'.config/hypr/lua/hyprlang.lua'
wall=h/'.config/hypr/scripts/StartupWallpaper.sh'
if 'HYPRLAND_NATIVE_PREVIOUS_LD_LIBRARY_PATH' not in lua.read_text() or 'HYPRLAND_NATIVE_ACTIVE' not in wall.read_text():
 raise SystemExit('Installed startup integration is older than this trial. No system settings changed.')
subprocess.run(['python3',str(h/'.config/hypr/scripts/StartupWallpaperCache.py')],check=True)
values=subprocess.check_output(['python3',str(h/'.config/hypr/scripts/StartupWallpaperCache.py'),'--native'],text=True).splitlines()
if len(values)!=4:raise SystemExit('No valid initial-image cache; trial setup stopped.')
repo=Path(os.environ['REPO_FOR_TRIAL'])
source=repo/'config/hypr/scripts/StartHyprland.py'
target=h/'.config/hypr/scripts/StartHyprland.py'
if target.read_bytes()!=source.read_bytes():
 import datetime,shutil
 backup=h/'.local/state/login-followup-backups'/datetime.datetime.now().strftime('%Y%m%d-%H%M%S-trial-launcher')
 backup.mkdir(parents=True);shutil.copy2(target,backup/target.name);shutil.copy2(source,target)
subprocess.run(['python3',str(target),'--prepare-launcher'],check=True)
PY
python3 "$HERE/experiments/aquamarine-startup/prepare-startup-trial.py"
sudo python3 "$HERE/installer/install-session.py" --trial
sudo python3 "$HERE/installer/select-session.py" "$(id -un)" --session hyprland-dotfiles-trial
cat <<'TEXT'
Prepared ONE experimental startup trial. Current desktop kept running.
At the next login, select “Hyprland (Fast startup trial)” if it is not preselected.
This uses a private backend library, not a replacement driver or system RPM.
An early failure retries the packaged watchdog once. Later logins use the packaged
backend automatically; the original Hyprland session remains available.
After that login, the logs will show whether the candidate ran and how long its
startup took. No speed improvement or solved blackout is claimed before that test.
TEXT

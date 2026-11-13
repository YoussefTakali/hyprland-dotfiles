"""Remove the exact GPU overrides left by older desktop installs."""
from pathlib import Path
import datetime
import shutil
h = Path.home()
b = h / '.local/state/desktop-login-backups' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
def backup(p):
    if p.exists():
        dest = b / p.relative_to(h)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, dest)

# Remove only the old repair's machine-specific managed block and preserve
# everything the user may have added after it.
p = h / '.config/uwsm/env-hyprland'
if p.exists():
    old = p.read_text()
    marker = '# BEGIN desktop-login-repair\n'
    lines = [marker,
        'export AQ_DRM_DEVICES="$(readlink -f /dev/dri/by-path/pci-0000:01:00.0-card)"\n',
        'export GBM_BACKEND=nvidia-drm\n',
        'export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json\n',
        'export __GLX_VENDOR_LIBRARY_NAME=nvidia\n']
    block = ''.join(lines)
    # An earlier version used a different comment for the same exact exports.
    earlier = '# NVIDIA startup repair: set these before the compositor loads EGL.\n' + ''.join(lines[1:])
    cleaned = old.replace(block, '', 1).replace(earlier, '', 1)
    if cleaned != old:
        backup(p)
        p.write_text(cleaned)

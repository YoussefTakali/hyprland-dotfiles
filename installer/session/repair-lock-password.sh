#!/usr/bin/env bash
# Fedora's stock hyprlock stack includes login -> system-auth -> fingerprint first.
# Keep password authentication and its failure delay through Fedora's password-auth stack.
set -euo pipefail
[[ $EUID == 0 ]] || { echo "Run: sudo bash $0" >&2; exit 1; }
[[ -f /etc/pam.d/password-auth && -f /etc/pam.d/hyprlock ]] || exit 1
# Refuse to overwrite a custom authentication stack.
if ! diff -u <(printf 'auth include login\n') <(sed -E '/^\s*(#|$)/d; s/[[:space:]]+/ /g; s/^ //; s/ $//' /etc/pam.d/hyprlock) >/dev/null; then
    echo 'hyprlock PAM is customized or already repaired; leaving it unchanged.'; exit 0
fi
backup="/var/backups/hyprlock-pam-$(date +%Y%m%d-%H%M%S)"
install -D -m 0644 /etc/pam.d/hyprlock "$backup"
printf '# Password authentication with the Fedora-managed password-auth stack.\nauth include password-auth\n' > /etc/pam.d/hyprlock
restorecon /etc/pam.d/hyprlock
echo "Applied password-only lock authentication. Backup: $backup"

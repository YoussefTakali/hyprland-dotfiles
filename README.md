# Hyprland dotfiles (Fedora)

My Hyprland desktop on Fedora, built on top of [JaKooLit's Fedora-Hyprland](https://github.com/JaKooLit/Fedora-Hyprland),
themed around Catppuccin Mocha + a wallust accent that follows the wallpaper.

## Install on a new machine

```sh
git clone https://github.com/YoussefTakali/hyprland-dotfiles.git
cd hyprland-dotfiles
./install.sh            # KooL base (if Hyprland isn't installed) + extra packages + these configs
./install.sh --sddm     # same, plus the SDDM login fix (French keyboard + visible cursor)
```

Existing configs are backed up to `~/.config-backup-<date>/` before anything is replaced.

On a fresh Fedora you only need `git` + `gh` (repo is private) — the script downloads and runs the
KooL Fedora-Hyprland installer itself. In that installer, say yes to: SDDM, GTK themes, Bibata cursor,
zsh + oh-my-zsh, quickshell, and the NVIDIA option if the machine has an NVIDIA GPU.

Not included: the full wallpaper collection (only the current wallpaper), and apps like Spotify/Firefox.

## What's in it

| Area | Highlights |
|---|---|
| Lock screen | Quickshell lock (`config/quickshell/lockscreen`): frosted wallpaper, music card with album art, cava bars, seek, prev/play/next, audio-output switcher, two-click power buttons, unlock animation. Secure session lock with hyprlock fallback (`hypr/scripts/QsLock.sh`). |
| Waybar | Wi-Fi + speed module, Bluetooth with device/battery, GPU usage next to CPU, privacy (mic/screen) indicator, recording indicator, clipboard button |
| Utilities | **Super+X** grid: screenshot, screen recorder, color picker, clipboard, calculator, emoji, Wi-Fi, Bluetooth, power profile, night light, OCR text grab, keybinds |
| Cheat sheet | **Super+H**: live keybinds grouped by category (rofi) |
| Menus | rofi theme `KooL_utilities` (blurred, rounded) for every popup; Wi-Fi/Bluetooth menus with VPN, hidden networks, pairing |
| Wallpaper | Super+W picks images **or videos** (mp4/mkv/mov/webm in ~/Pictures/wallpapers); videos play with mpvpaper, pause under fullscreen apps, theme colors come from a frame, and the video comes back after reboot |
| Windows | solid accent border, soft accent glow, rounded corners |
| Terminal | kitty with Catppuccin Mocha + JetBrains Mono, wallpaper startup card (fastfetch), readable `agnosterzak-mocha` prompt |
| GTK apps | translucent Catppuccin + mauve style for GTK3/GTK4 apps (Nautilus, settings windows), mauve folder icons |

## Keys

| Keys | Action |
|---|---|
| Super+L | lock |
| Super+X | utilities hub |
| Super+H | cheat sheet |
| Super+Alt+Print | start/stop screen recording |
| Super+Alt+X / Super+Alt+T | color picker / text grab (OCR) |

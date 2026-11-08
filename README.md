<h1 align="center">Hyprland Desktop</h1>

<p align="center">
  <b>A polished Hyprland desktop for Fedora</b><br>
  Catppuccin Mocha · wallust adaptive accents · Quickshell lock screen · Waybar · rofi
</p>

<p align="center">
  <img src="assets/desktop.png" alt="Desktop" width="100%">
</p>

## Demo

<p align="center">
  <img src="assets/demo.webp" alt="Demo: app launcher, terminal, power menu, utilities hub, lock screen and wallpaper switching" width="100%">
</p>

<p align="center"><i>App launcher, terminal, power menu, utilities hub, lock screen, and a wallpaper switch where every colour follows the new wallpaper (1.5× speed).<br>
Full-quality recording: <a href="assets/demo.mp4">demo.mp4</a></i></p>

## Screenshots

### Lock screen
<img src="assets/lockscreen.png" alt="Lock screen" width="100%">

### Lock screen: ambient mode
<img src="assets/lockscreen-ambient.png" alt="Lock screen ambient mode" width="100%">

### Power menu
<img src="assets/powermenu.png" alt="Power menu" width="100%">

### Utilities hub (Super+X)
<img src="assets/utilities.png" alt="Utilities hub" width="100%">

### Terminal
<img src="assets/terminal.png" alt="Terminal with fastfetch" width="100%">

### Waybar
<img src="assets/waybar.png" alt="Waybar" width="100%">

## Features

- **Lock screen** — 4 switchable styles (Slate, Iris, Fog, Cards). Frosted wallpaper, music controls with album art and cava visualizer, weather, battery, ambient mode. Secure Wayland session lock with hyprlock fallback.
- **Power menu** — animated orbs with a 3-second countdown ring. Lock, sleep, logout, restart, shutdown.
- **Volume & brightness OSD** — glass pill overlay with accent-colored progress bar, follows your wallpaper theme.
- **Waybar** — adaptive colors from wallpaper. Wi-Fi with speed, Bluetooth with battery, GPU/CPU, privacy indicators, cava visualizer.
- **Utilities hub** (Super+X) — screenshot, screen recorder, color picker, clipboard, calculator, emoji, Wi-Fi, Bluetooth, power profiles, night light, OCR, lock screen style switcher.
- **Keyboard Shortcuts GUI** — add and edit shortcuts without config files.
- **Video wallpapers** — Super+W picks images or videos; mpvpaper with hardware decoding, pauses under fullscreen, restores on reboot.
- **Spotify integration** — runs in the background, toggle with Super+Alt+M, Super+Q hides instead of closing.
- **Adaptive theming** — wallust extracts colors from wallpaper; AccentGuard ensures WCAG-readable accents across Waybar, GTK, kitty, and the lock screen.
- **Hyprland 0.57 Lua** — full compatibility layer that loads `.conf` files through the new Lua config, with auto-reload.

## GPU Support

Automatic detection and configuration for:
- **NVIDIA** — open kernel modules (akmod), PRIME offload for hybrid laptops, Secure Boot MOK signing, VA-API, suspend/resume
- **AMD** — mesa freeworld drivers, PRIME offload for hybrid setups, VA-API with radeonsi
- **Intel** — iHD media driver, hybrid GPU pairing

Run `~/.config/hypr/scripts/GpuInfo.sh` to see your detected setup.

## Install

### Graphical Installer (recommended)

```sh
git clone https://github.com/YoussefTakali/hyprland-dotfiles.git
cd hyprland-dotfiles
./setup
```

A GTK4 installer walks you through package installation, driver setup, and configuration.

### CLI

```sh
./install.sh            # base install + configs
./install.sh --sddm     # with SDDM login manager
```

**Requirements:** fresh Fedora with `git` installed. The installer handles everything else — KooL base, packages, GPU drivers, configs, and theming.

Existing configs are backed up to `~/.config-backup-<date>/` before replacement.

## Keyboard Shortcuts

| Keys | Action |
|---|---|
| Super+Enter | terminal (kitty) |
| Super+L | lock |
| Super+X | utilities hub |
| Super+H | cheat sheet |
| Super+Q | close window (hides Spotify) |
| Super+W | wallpaper picker |
| Super+Alt+M | toggle Spotify |
| Super+Alt+Print | start/stop screen recording |
| Super+Alt+X | color picker |
| Super+Alt+T | text grab (OCR) |

## Credits

Built on top of [JaKooLit's Fedora-Hyprland](https://github.com/JaKooLit/Fedora-Hyprland) with [Catppuccin Mocha](https://github.com/catppuccin/catppuccin) theming and [wallust](https://codeberg.org/explosion-mental/wallust) color extraction.

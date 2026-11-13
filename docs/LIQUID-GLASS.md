# Liquid Glass Waybar

Select `[Glass] Liquid Glass` with Super+Ctrl+B (style menu), or run:

```bash
bash ~/.config/hypr/scripts/WaybarMode.sh liquid
```

Super+Alt+B opens the layout menu; choosing `[TOP] Liquid Glass` also selects its
style. Light translucent panels reveal the wallpaper/windows behind them with
compositor blur. This approximates glass using GTK CSS and Hyprland blur; it does
not implement Apple's optical refraction.

The mode sets a low Waybar ignore_alpha threshold so translucent pixels are blurred,
and reloads Waybar without restarting other desktop services. Selecting another
style removes the glass blur override. Backdrop colors appear through transparency;
no wallpaper color sampling process runs continuously.

Install options: `./install.sh --bar=liquid`, or select Liquid glass in the graphical
installer. Dependencies waybar, gtk3 and gtk-layer-shell are included. Validation
covers GTK CSS parsing and mode switching, not live compositor appearance.

## V2: one continuous strip

V1 keeps its three floating panels. Select `[Glass] Liquid Glass V2` with
Super+Ctrl+B, or `[TOP] Liquid Glass V2` with Super+Alt+B. Both choose matching
layout and style. Direct selection:

```bash
bash ~/.config/hypr/scripts/WaybarMode.sh liquid-v2
```

V2 draws one glass surface across the full bar, including the spaces between left,
clock and right controls. It retains V1's colors, blur, hover feedback and controls.
Install with `./install.sh --bar=liquid-v2` or the graphical installer's V2 option.

V2 is self-contained: GTK resolves relative imports against the `style.css` symlink
location, so importing a neighboring stylesheet from V2 would fail at runtime.
`python3 tests/test_waybar_styles.py` verifies both styles through that symlink.

## V3: open-application details

V3 uses the same continuous glass surface as V2. It adds live app icons (click to
focus), highlights the active app, and shows the focused window title with an app
icon. Hover to see its app class and full title. Numbered workspace buttons reveal
open-window titles on hover. The clock includes the date; the hardware drawer and
audio tooltips expose additional usage and output details. These are native Waybar
modules, without a new polling script. App icons require Hyprland's foreign-toplevel
protocol, as used by Waybar's wlr/taskbar module.

Choose `[Glass] Liquid Glass V3` with Super+Ctrl+B, or run:

```bash
bash ~/.config/hypr/scripts/WaybarMode.sh liquid-v3
```

Both installers offer V3 (`./install.sh --bar=liquid-v3`). Styles are self-contained
and checked through Waybar's `style.css` symlink. Live app switching still needs a
desktop check.

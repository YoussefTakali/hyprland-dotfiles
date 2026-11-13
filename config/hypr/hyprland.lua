-- Select the sole display-connected GPU. Never pin a friend's card or PCI slot.
local probe = io.popen('bash "' .. os.getenv("HOME") .. '/.config/hypr/scripts/GpuPrimary.sh"')
if probe then
    local line = probe:read("*l") or ""
    probe:close()
    local device, vendor = line:match("^([/:%w]+) (0x%x+)$")
    if device then
        hl.env("AQ_DRM_DEVICES", device)
        -- Retain both GLVND/GBM vendors for fallback and monitor hotplug.
    end
end

-- Hyprland reads this file (0.55+; from 0.57 it is the only format).
-- It loads the classic hyprland.conf tree (KooL base + this desktop) through lua/hyprlang.lua, so every .conf
-- file, the scripts that edit them and the Keyboard Shortcuts app keep working. Problems are listed in
-- ~/.cache/hyprlang-compat.log. To go back on Hyprland 0.56 or older: delete this file and log in again.
require("lua.hyprlang").load(os.getenv("HOME") .. "/.config/hypr/hyprland.conf")

-- GSettings synchronization blocked the first cursor load in the startup trace.
-- Preserve existing GTK settings during initial construction; restore automatic
-- synchronization after the first wallpaper so later theme changes work normally.
if os.getenv("HYPRLAND_CURSOR_INITIALIZED") ~= "1" then
    local sync = hl.get_config("cursor.sync_gsettings_theme")
    if sync == true or sync == 1 then
        hl.config({ cursor = { sync_gsettings_theme = false } })
        hl.env("HYPRLAND_DEFERRED_CURSOR_SYNC", "1")
    end
    hl.env("HYPRLAND_CURSOR_INITIALIZED", "1")
end

-- The measured-login launcher enables native timestamps only until the still
-- has been submitted. Normal sessions retain the user's logging preferences.
if os.getenv("HYPRLAND_LOGIN_PROFILE") == "1" then
    hl.config({ debug = { disable_logs = false, disable_time = false } })
end

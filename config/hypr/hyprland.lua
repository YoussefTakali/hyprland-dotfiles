-- Hyprland reads this file (0.55+; from 0.57 it is the only format).
-- It loads the classic hyprland.conf tree (KooL base + this desktop) through lua/hyprlang.lua, so every .conf
-- file, the scripts that edit them and the Keyboard Shortcuts app keep working. Problems are listed in
-- ~/.cache/hyprlang-compat.log. To go back on Hyprland 0.56 or older: delete this file and log in again.
require("lua.hyprlang").load(os.getenv("HOME") .. "/.config/hypr/hyprland.conf")

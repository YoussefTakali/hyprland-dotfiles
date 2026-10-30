-- hyprlang.lua — run a classic hyprland.conf (hyprlang) tree on Hyprland's Lua config (0.55+, required from 0.57).
--
--   hyprland.lua:   require("lua.hyprlang").load(os.getenv("HOME") .. "/.config/hypr/hyprland.conf")
--
-- Every time Hyprland loads its config, the .conf files are read and applied through the hl.* Lua API, so the
-- files, the scripts that edit them and the users who know them keep working. Values are converted to the type
-- the running Hyprland expects, read from its own API stubs (/usr/share/hypr/stubs/hl.meta.lua).
-- Anything that can't be applied is skipped, logged to ~/.cache/hyprlang-compat.log and shown in a notification;
-- the rest of the config still loads. Set HYPRLANG_STRICT=1 to make problems fail the load (for testing).
-- Written 2026-10-30 for the hyprland-dotfiles desktop. MIT licence.

local M = {}

local HOME = os.getenv("HOME") or ""
local STUBS = "/usr/share/hypr/stubs/hl.meta.lua"
local LOG = HOME .. "/.cache/hyprlang-compat.log"

local vars = {}           -- $variables
local problems = {}       -- { "file:line: message", ... }
local stats = { files = 0, binds = 0, rules = 0, options = 0, execs = 0, other = 0 }
local exec_once = {}
local exec_shutdown = {}
local devices = {}        -- device { ... } blocks
local loaded = {}         -- files already sourced (no loops)
local types, classes      -- from the stubs

-- ── small helpers ────────────────────────────────────────────────────────────
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function split(s, sep, max)
    local out, start = {}, 1
    while true do
        if max and #out == max - 1 then out[#out + 1] = s:sub(start); break end
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start); break end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + #sep
    end
    for i, v in ipairs(out) do out[i] = trim(v) end
    return out
end

local function words(s)
    local out = {}
    for w in s:gmatch("%S+") do out[#out + 1] = w end
    return out
end

local function problem(where, msg)
    problems[#problems + 1] = (where or "?") .. ": " .. tostring(msg)
end

-- hyprlang comments: "#" starts one, "##" is a literal "#"
local function strip_comment(line)
    if line:match("^%s*#") then return "" end          -- a whole-line comment (also "## Section ##")
    local out, i, n = {}, 1, #line
    while i <= n do
        local c = line:sub(i, i)
        if c == "#" then
            if line:sub(i + 1, i + 1) == "#" then out[#out + 1] = "#"; i = i + 2
            else break end
        else
            out[#out + 1] = c; i = i + 1
        end
    end
    return trim(table.concat(out))
end

-- $vars are replaced; unknown ones ($HOME…) stay for the shell
local function expand(s)
    return (s:gsub("%$([%w_]+)", function(name)
        local v = vars[name]
        return v ~= nil and v or ("$" .. name)
    end))
end

-- for paths: also environment variables and ~
local function expand_path(s)
    s = expand(s)
    s = s:gsub("%$([%w_]+)", function(name) return os.getenv(name) or ("$" .. name) end)
    s = s:gsub("^~", HOME)
    return s
end

local BOOL = { ["true"] = true, yes = true, on = true, ["1"] = true,
               ["false"] = false, no = false, off = false, ["0"] = false }

local function to_bool(v)
    local b = BOOL[v:lower()]
    if b == nil then return nil end
    return b
end

-- ── types from Hyprland's own stubs ──────────────────────────────────────────
local function load_stubs()
    types, classes = {}, {}
    local f = io.open(STUBS, "r")
    if not f then return end
    local class
    for line in f:lines() do
        local key, t = line:match("^%-%-%-@field %['([^']+)'%] (%S+)")
        if key then types[key] = t end
        local c = line:match("^%-%-%-@class ([%w_.]+)")
        if c then class = c; classes[c] = {} elseif not line:match("^%-%-%-@field") then class = nil end
        local field, ft = line:match("^%-%-%-@field ([%w_]+)%??%s+(%S+)")
        if class and field then classes[class][field] = ft end
    end
    f:close()
end

local function is_color(tok)
    return tok:match("^rgba?%(") or tok:match("^0x%x+$") or tok:match("^%x%x%x%x%x%x%x?%x?$")
end

-- string from the .conf -> value of the given stub type
local function convert(value, t)
    t = t or ""
    if t:find("Gradient", 1, true) then
        local cols, angle = {}, nil
        for _, w in ipairs(words(value)) do
            local deg = w:match("^(%-?[%d.]+)deg$")
            if deg then angle = tonumber(deg) elseif is_color(w) then cols[#cols + 1] = w end
        end
        if #cols > 1 or angle then return { colors = cols, angle = angle } end
        return value
    end
    if t:find("Vec2", 1, true) then
        local w = words(value)
        if #w == 2 and tonumber(w[1]) and tonumber(w[2]) then return { tonumber(w[1]), tonumber(w[2]) } end
        return value
    end
    if t:find("CssGap", 1, true) then
        local w = words(value)
        if #w == 1 then return tonumber(w[1]) or value end
        local n = {}
        for i, x in ipairs(w) do n[i] = tonumber(x) end
        if #w == 2 then return { top = n[1], bottom = n[1], right = n[2], left = n[2] } end
        if #w == 4 then return { top = n[1], right = n[2], bottom = n[3], left = n[4] } end
        return value
    end
    local wants_bool = t:find("boolean", 1, true)
    local wants_num = t:find("integer", 1, true) or t:find("number", 1, true)
    if t == "boolean" then
        local b = to_bool(value)
        if b ~= nil then return b end
    end
    if wants_num then
        local n = tonumber(value)
        if n then return n end
    end
    if wants_bool then
        local b = to_bool(value)
        if b ~= nil then return b end
    end
    if t == "" then                                   -- untyped: best guess
        local b = to_bool(value)
        if b ~= nil and not tonumber(value) then return b end
        return tonumber(value) or value
    end
    return value
end

-- loose conversion for rule effects / match props (untyped in the stubs)
local function loose(value)
    if value == nil or value == "" then return true end
    local b = BOOL[value:lower()]
    if b ~= nil and not value:match("^%d$") then return b end
    if value == "1" or value == "0" then return value == "1" end
    return tonumber(value) or value
end

-- ── options (sections) ───────────────────────────────────────────────────────
local function set_option(path, raw, where)
    if next(types) and types[path] == nil and types[(path:gsub("%-", "_"))] ~= nil then
        path = path:gsub("%-", "_")                      -- tap-to-click -> tap_to_click
    end
    if next(types) and types[path] == nil then
        return problem(where, "unknown option '" .. path .. "' (removed or renamed in Hyprland " .. (hl.version and hl.version() or "") .. ")")
    end
    local value = convert(raw, types[path])
    local tbl = {}
    local cur = tbl
    local parts = split(path, ".")
    for i = 1, #parts - 1 do cur[parts[i]] = {}; cur = cur[parts[i]] end
    cur[parts[#parts]] = value
    local ok, err = pcall(hl.config, tbl)
    if ok then stats.options = stats.options + 1 else problem(where, path .. " = " .. raw .. ": " .. tostring(err)) end
end

-- ── dispatchers: legacy name + argument -> hl.dsp.* ──────────────────────────
local DIR = { l = "left", r = "right", u = "up", d = "down", t = "up", b = "down",
              left = "left", right = "right", up = "up", down = "down" }

local function ws(arg)
    arg = trim(arg)
    return tonumber(arg) or arg
end

local function exec_with_rules(arg)
    local rules, cmd = arg:match("^%s*%[(.-)%]%s*(.*)$")
    if not rules then return hl.dsp.exec_cmd(arg) end
    local t = {}
    for _, r in ipairs(split(rules, ";")) do
        local name, v = r:match("^(%S+)%s*(.*)$")
        if name then t[name] = loose(v) end
    end
    return hl.dsp.exec_cmd(cmd, t)
end

local D = {}
D.exec = exec_with_rules
D.execr = function(a) return hl.dsp.exec_raw(a) end
D.killactive = function() return hl.dsp.window.close() end
D.closewindow = function(a) return hl.dsp.window.close({ window = a }) end
D.forcekillactive = function() return hl.dsp.window.kill() end
D.killwindow = function(a) return hl.dsp.window.kill({ window = a }) end
D.workspace = function(a) return hl.dsp.focus({ workspace = ws(a) }) end
D.movetoworkspace = function(a)
    local w, win = a:match("^([^,]+),(.+)$")
    if a:match("^special$") then a = "special:special" end
    return hl.dsp.window.move({ workspace = ws(w or a), window = win and trim(win) or nil, follow = true })
end
D.movetoworkspacesilent = function(a)
    local w, win = a:match("^([^,]+),(.+)$")
    if a:match("^special$") then a = "special:special" end
    return hl.dsp.window.move({ workspace = ws(w or a), window = win and trim(win) or nil, follow = false })
end
D.togglefloating = function(a) return hl.dsp.window.float({ action = "toggle", window = a ~= "" and a or nil }) end
D.setfloating = function(a) return hl.dsp.window.float({ action = "enable", window = a ~= "" and a or nil }) end
D.settiled = function(a) return hl.dsp.window.float({ action = "disable", window = a ~= "" and a or nil }) end
D.fullscreen = function(a)
    local mode = (a == "1") and "maximized" or "fullscreen"
    return hl.dsp.window.fullscreen({ mode = mode })
end
D.pseudo = function() return hl.dsp.window.pseudo() end
D.pin = function(a) return hl.dsp.window.pin({ window = a ~= "" and a or nil }) end
D.centerwindow = function() return hl.dsp.window.center() end
D.movefocus = function(a) return hl.dsp.focus({ direction = DIR[a] or a }) end
D.movewindow = function(a)
    local mon = a:match("^mon:(.+)$")
    if mon then return hl.dsp.window.move({ monitor = mon }) end
    if a == "" then return hl.dsp.window.drag() end
    return hl.dsp.window.move({ direction = DIR[a] or a })
end
D.swapwindow = function(a) return hl.dsp.window.swap({ direction = DIR[a] or a }) end
D.swapnext = function(a) return a == "prev" and hl.dsp.window.swap({ prev = true }) or hl.dsp.window.swap({ next = true }) end
D.resizeactive = function(a)
    local exact, rest = a:match("^(exact)%s+(.+)$")
    local w = words(rest or a)
    return hl.dsp.window.resize({ x = tonumber(w[1]) or w[1], y = tonumber(w[2]) or w[2], relative = not exact })
end
D.moveactive = function(a)
    local exact, rest = a:match("^(exact)%s+(.+)$")
    local w = words(rest or a)
    return hl.dsp.window.move({ x = tonumber(w[1]) or w[1], y = tonumber(w[2]) or w[2], relative = not exact })
end
D.resizewindow = function(a) return hl.dsp.window.resize(a == "1" and { keep_aspect_ratio = true } or nil) end
D.cyclenext = function(a)
    local o = {}
    for _, w in ipairs(words(a)) do
        if w == "prev" then o.next = false elseif w == "tiled" then o.tiled = true elseif w == "floating" then o.floating = true end
    end
    return hl.dsp.window.cycle_next(o)
end
D.bringactivetotop = function() return hl.dsp.window.alter_zorder({ mode = "top" }) end
D.alterzorder = function(a)
    local mode, win = a:match("^([^,]+),?(.*)$")
    return hl.dsp.window.alter_zorder({ mode = trim(mode), window = win ~= "" and trim(win) or nil })
end
D.focuswindow = function(a) return hl.dsp.focus({ window = a }) end
D.focusmonitor = function(a) return hl.dsp.focus({ monitor = a }) end
D.focuscurrentorlast = function() return hl.dsp.focus({ last = true }) end
D.focusurgentorlast = function() return hl.dsp.focus({ urgent_or_last = true }) end
D.togglegroup = function() return hl.dsp.group.toggle() end
D.changegroupactive = function(a)
    if a == "b" then return hl.dsp.group.prev() end
    if tonumber(a) then return hl.dsp.group.active({ index = tonumber(a) }) end
    return hl.dsp.group.next()
end
D.moveintogroup = function(a) return hl.dsp.window.move({ into_group = DIR[a] or a }) end
D.moveoutofgroup = function(a) return hl.dsp.window.move({ out_of_group = (a ~= "" and (DIR[a] or a)) or true }) end
D.lockgroups = function(a) return hl.dsp.group.lock({ all = true, action = a ~= "" and a or nil }) end
D.lockactivegroup = function(a) return hl.dsp.group.lock({ action = a ~= "" and a or nil }) end
D.togglespecialworkspace = function(a) return hl.dsp.workspace.toggle_special(a ~= "" and a or "special") end
D.movecurrentworkspacetomonitor = function(a) return hl.dsp.workspace.move({ monitor = DIR[a] or a }) end
D.moveworkspacetomonitor = function(a)
    local w, m = a:match("^(%S+)%s+(%S+)$")
    return hl.dsp.workspace.move({ workspace = ws(w or a), monitor = m })
end
D.swapactiveworkspaces = function(a)
    local m1, m2 = a:match("^(%S+)%s+(%S+)$")
    return hl.dsp.workspace.swap_monitors({ monitor1 = m1, monitor2 = m2 })
end
D.renameworkspace = function(a)
    local id, name = a:match("^(%S+)%s*(.*)$")
    return hl.dsp.workspace.rename({ workspace = ws(id), name = name ~= "" and name or nil })
end
D.layoutmsg = function(a) return hl.dsp.layout(a) end
D.togglesplit = function() return hl.dsp.layout("togglesplit") end
D.swapsplit = function() return hl.dsp.layout("swapsplit") end
D.exit = function() return hl.dsp.exit() end
D.submap = function(a) return hl.dsp.submap(a) end
D.pass = function(a) return hl.dsp.pass({ window = a }) end
D.global = function(a) return hl.dsp.global(a) end
D.dpms = function(a)
    local action, mon = a:match("^(%S*)%s*(.*)$")
    return hl.dsp.dpms({ action = action ~= "" and action or nil, monitor = mon ~= "" and mon or nil })
end
D.forcerendererreload = function() return hl.dsp.force_renderer_reload() end
D.event = function(a) return hl.dsp.event(a) end
D.tagwindow = function(a)
    local tag, win = a:match("^(%S+)%s*(.*)$")
    return hl.dsp.window.tag({ tag = tag, window = win ~= "" and win or nil })
end
D.setprop = function(a)
    local win, prop, value = a:match("^(%S+)%s+(%S+)%s+(.+)$")
    return hl.dsp.window.set_prop({ window = win, prop = prop, value = value })
end
D.signal = function(a) return hl.dsp.window.signal({ signal = tonumber(a) or a }) end
D.sendshortcut = function(a)
    local p = split(a, ",")
    return hl.dsp.send_shortcut({ mods = p[1], key = p[2], window = p[3] })
end

local function dispatcher(name, arg, where)
    local f = D[name:lower()]
    if not f then return nil, "unknown dispatcher '" .. name .. "'" end
    local ok, d = pcall(f, arg or "")
    if not ok then return nil, name .. " " .. (arg or "") .. ": " .. tostring(d) end
    return d
end

-- ── binds ────────────────────────────────────────────────────────────────────
local FLAGS = { l = "locked", r = "release", c = "click", g = "drag", o = "long_press", e = "repeating",
                n = "non_consuming", m = "mouse", t = "transparent", i = "ignore_mods", p = "dont_inhibit",
                u = "submap_universal", k = "allow_input_capture" }

-- keysyms the old parser took case-insensitively (or that never existed) -> the name Lua's strict parser wants
local KEYSYM_FIX = { xf86audioplaypause = "XF86AudioPlay" }

local function key_string(mods, key)
    key = KEYSYM_FIX[key:lower()] or key
    local parts = {}
    for tok in mods:gmatch("[^%s+]+") do
        local name, side = tok:match("^(%a+)_([LRlr])$")
        if name then                                     -- ALT_L: a single modifier *key* -> keysym "Alt_L"
            local n = name:lower()
            n = ({ ctrl = "control", win = "super", mod4 = "super" })[n] or n
            parts[#parts + 1] = n:sub(1, 1):upper() .. n:sub(2) .. "_" .. side:upper()
        else
            for m in tok:gmatch("[^_]+") do parts[#parts + 1] = m:upper() end   -- SUPER_SHIFT -> SUPER + SHIFT
        end
    end
    local kname, kside = key:match("^(%a+)_([LRlr])$")
    if kname and ({ alt = 1, shift = 1, super = 1, ctrl = 1, control = 1, meta = 1, hyper = 1 })[kname:lower()] then
        local n = kname:lower() == "ctrl" and "control" or kname:lower()
        key = n:sub(1, 1):upper() .. n:sub(2) .. "_" .. kside:upper()
    end
    parts[#parts + 1] = key
    return table.concat(parts, " + ")
end

local function do_bind(kw, value, where)
    local flags = kw:sub(5)
    local has_desc = flags:find("d", 1, true)
    local n = has_desc and 4 or 3
    local f = split(value, ",", n + 1)
    if #f < n then return problem(where, "bind needs at least " .. n .. " fields: " .. value) end
    local mods, key = f[1], f[2]
    local desc = has_desc and f[3] or nil
    local disp = f[n]
    local arg = f[n + 1] or ""
    local opts = {}
    for c in flags:gmatch(".") do
        if FLAGS[c] then opts[FLAGS[c]] = true end
    end
    if desc and desc ~= "" then opts.description = desc end
    local d, err
    if opts.mouse then
        local name = disp:lower()
        if name == "movewindow" then d = hl.dsp.window.drag()
        elseif name == "resizewindow" then d = hl.dsp.window.resize(arg == "1" and { keep_aspect_ratio = true } or nil)
        else d, err = dispatcher(disp, arg, where) end
    else
        d, err = dispatcher(disp, arg, where)
    end
    if not d then return problem(where, err) end
    local ok, e = pcall(hl.bind, key_string(mods, key), d, next(opts) and opts or nil)
    if ok then stats.binds = stats.binds + 1 else problem(where, "bind " .. value .. ": " .. tostring(e)) end
end

local function do_unbind(value, where)
    local f = split(value, ",", 2)
    local ok, e = pcall(hl.unbind, key_string(f[1] or "", f[2] or ""))
    if not ok then problem(where, "unbind " .. value .. ": " .. tostring(e)) end
end

-- ── rules ────────────────────────────────────────────────────────────────────
local function do_rule(kind, value, where)
    local spec, match = {}, {}
    for _, part in ipairs(split(value, ",")) do
        local prop, v = part:match("^match:(%S+)%s*(.*)$")
        if prop then
            match[prop] = loose(v)
        else
            local name, v2 = part:match("^(%S+)%s*(.*)$")
            if name then spec[name] = loose(v2) end
        end
    end
    if next(match) then spec.match = match end
    local ok, e = pcall(kind == "windowrule" and hl.window_rule or hl.layer_rule, spec)
    if ok then stats.rules = stats.rules + 1 else problem(where, kind .. " " .. value .. ": " .. tostring(e)) end
end

-- ── other keywords ───────────────────────────────────────────────────────────
local function do_monitor(value, where)
    local f = split(value, ",")
    local spec = { output = f[1] or "" }
    if f[2] == "disable" or f[2] == "disabled" then
        spec.disabled = true
    else
        spec.mode, spec.position = f[2], f[3]
        if f[4] then spec.scale = tonumber(f[4]) or f[4] end
        local i = 5
        while f[i] do
            local k, v = f[i], f[i + 1] or ""
            local t = classes and classes["HL.MonitorSpec"] and classes["HL.MonitorSpec"][k]
            spec[k] = convert(v, t)
            i = i + 2
        end
    end
    local ok, e = pcall(hl.monitor, spec)
    if ok then stats.other = stats.other + 1 else problem(where, "monitor " .. value .. ": " .. tostring(e)) end
end

local WS_KEYS = { gapsin = "gaps_in", gapsout = "gaps_out", bordersize = "border_size", defaultName = "default_name",
                  ["on-created-empty"] = "on_created_empty", layoutopt = "layout_opts" }

local function do_workspace(value, where)
    local f = split(value, ",")
    local spec = { workspace = f[1] }
    for i = 2, #f do
        local k, v = f[i]:match("^([^:]+):%s*(.*)$")
        if k then
            if k == "rounding" then spec.no_rounding = not to_bool(v)
            elseif k == "shadow" then spec.no_shadow = not to_bool(v)
            elseif k == "border" then spec.no_border = not to_bool(v)
            else
                k = WS_KEYS[k] or k
                local t = classes and classes["HL.WorkspaceRuleSpec"] and classes["HL.WorkspaceRuleSpec"][k]
                spec[k] = convert(v, t)
            end
        end
    end
    local ok, e = pcall(hl.workspace_rule, spec)
    if ok then stats.rules = stats.rules + 1 else problem(where, "workspace " .. value .. ": " .. tostring(e)) end
end

local function do_gesture(value, where)
    local f = split(value, ",")
    local spec = { fingers = tonumber(f[1]), direction = f[2] }
    local action = {}
    for i = 3, #f do
        local k, v = f[i]:match("^(%a+):%s*(.*)$")
        if k == "mod" then spec.mods = v
        elseif k == "scale" then spec.scale = tonumber(v)
        else action[#action + 1] = f[i] end
    end
    spec.action = table.concat(action, ", ")
    local dname, darg = spec.action:match("^dispatcher%s*,%s*([^,]+),?%s*(.*)$")
    if dname then                                        -- "dispatcher, exec, cmd" -> a Lua function
        local d, err = dispatcher(trim(dname), darg, where)
        if not d then return problem(where, "gesture " .. value .. ": " .. tostring(err)) end
        spec.action = function() hl.dispatch(d) end
    end
    local ok, e = pcall(hl.gesture, spec)
    if ok then stats.other = stats.other + 1 else problem(where, "gesture " .. value .. ": " .. tostring(e)) end
end

local function do_animation(value, where)
    local f = split(value, ",")
    local spec = { leaf = f[1], enabled = f[2] ~= "0" }
    if spec.enabled then
        spec.speed = tonumber(f[3]) and math.min(tonumber(f[3]), 100)   -- the old parser capped silently
        spec.bezier = f[4]
        if f[5] and f[5] ~= "" then spec.style = f[5] end
    end
    local ok, e = pcall(hl.animation, spec)
    if ok then stats.other = stats.other + 1 else problem(where, "animation " .. value .. ": " .. tostring(e)) end
end

local function do_bezier(value, where)
    local f = split(value, ",")
    local p = {}
    for i = 2, 5 do p[i - 1] = tonumber(f[i]) end
    local ok, e = pcall(hl.curve, f[1], { type = "bezier", points = { { p[1], p[2] }, { p[3], p[4] } } })
    if ok then stats.other = stats.other + 1 else problem(where, "bezier " .. value .. ": " .. tostring(e)) end
end

local function do_env(value, where)
    local name, v = value:match("^([^,]+),(.*)$")
    if not name then return problem(where, "env needs NAME,value: " .. value) end
    local ok, e = pcall(hl.env, trim(name), trim(v))
    if ok then stats.other = stats.other + 1 else problem(where, "env " .. value .. ": " .. tostring(e)) end
end

-- ── the file reader ──────────────────────────────────────────────────────────
local load_file

local function source(value, where)
    local path = expand_path(value)
    if path:find("[*?]") then
        local p = io.popen("ls -1d " .. path .. " 2>/dev/null")
        if p then
            for f in p:lines() do load_file(f) end
            p:close()
        end
    else
        load_file(path, where)
    end
end

local keyword_inner
local function keyword(key, value, where, section)
    local handled = keyword_inner(key, value, where, section)
    return handled ~= false
end

function keyword_inner(key, value, where, section)
    if key:match("^bind") then do_bind(key, value, where); return true end
    if key == "unbind" then do_unbind(value, where); return true end
    if key == "windowrule" or key == "layerrule" then do_rule(key, value, where); return true end
    if key == "source" then source(value, where); return true end
    if key == "exec-once" then exec_once[#exec_once + 1] = value; stats.execs = stats.execs + 1; return true end
    if key == "exec-shutdown" then exec_shutdown[#exec_shutdown + 1] = value; return true end
    if key == "exec" then
        local ok, e = pcall(hl.exec_cmd, value)
        if not ok then problem(where, "exec " .. value .. ": " .. tostring(e)) end
        stats.execs = stats.execs + 1
        return true
    end
    if key == "env" then do_env(value, where); return true end
    if key == "monitor" then do_monitor(value, where); return true end
    if key == "workspace" and section == "" then do_workspace(value, where); return true end
    if key == "gesture" then do_gesture(value, where); return true end
    if key == "animation" then do_animation(value, where); return true end
    if key == "bezier" then do_bezier(value, where); return true end
    if key == "submap" or key == "plugin" or key == "permission" then
        problem(where, key .. " is not supported by the compatibility layer yet; write it in Lua")
        return true
    end
    return false
end

function load_file(path, from)
    if loaded[path] then return end
    local f = io.open(path, "r")
    if not f then return problem(from or path, "can't open " .. path) end
    loaded[path] = true
    stats.files = stats.files + 1
    local short = path:gsub("^" .. HOME:gsub("%p", "%%%0"), "~")
    local stack = {}                 -- section names
    local device = nil
    local n = 0
    for raw in f:lines() do
        n = n + 1
        local where = short .. ":" .. n
        local line = strip_comment(raw)
        if line ~= "" then
            local open = line:match("^([%w_%-%.:]+)%s*{$")
            if open then
                if open == "device" and #stack == 0 then device = {} end
                stack[#stack + 1] = open
            elseif line == "}" then
                local closed = table.remove(stack)
                if closed == "device" and #stack == 0 and device then
                    devices[#devices + 1] = { spec = device, where = where }
                    device = nil
                end
            else
                local key, value = line:match("^([^=]-)%s*=%s*(.*)$")
                if not key then
                    problem(where, "can't read this line: " .. line)
                else
                    key = trim(key)
                    if key:sub(1, 1) == "$" then
                        vars[key:sub(2)] = expand(value)
                    else
                        value = expand(value)
                        local section = table.concat(stack, ".")
                        if device then
                            local t = classes and classes["HL.DeviceSpec"] and classes["HL.DeviceSpec"][key]
                            device[key] = (key == "name") and value or convert(value, t)
                        elseif not keyword(key, value, where, section) then
                            -- an option: "general { gaps_in = 4 }" or "general:gaps_in = 4"
                            local path = key:gsub(":", ".")
                            if section ~= "" then path = section .. "." .. path end
                            set_option(path, value, where)
                        end
                    end
                end
            end
        end
    end
    f:close()
end

-- ── live commands (used by bin/hyprctl for scripts that call "hyprctl keyword/dispatch") ─
-- Old-style dispatch: hyprlang.dispatch("workspace", "2")
function M.dispatch(name, arg)
    local d, err = dispatcher(trim(name), trim(arg or ""), "hyprctl")
    if not d then error(err, 0) end
    hl.dispatch(d)
end

-- Old-style keyword: hyprlang.keyword("general:gaps_in", "8"), ("windowrule", "..."), ("bind", "...")
function M.keyword(key, value)
    local before = #problems
    key, value = trim(key), expand(trim(value or ""))
    if not keyword(key, value, "hyprctl", "") then
        set_option((key:gsub(":", ".")), value, "hyprctl")
    end
    if #problems > before then error(problems[#problems], 0) end
end

-- ── public ───────────────────────────────────────────────────────────────────
function M.load(path)
    hyprlang = M                                        -- global, for `hyprctl eval "hyprlang.…"`
    -- programs started by Hyprland find bin/hyprctl first: it turns old "hyprctl keyword/dispatch" into Lua
    local bin = HOME .. "/.config/hypr/bin"
    local path_now = os.getenv("PATH") or "/usr/bin:/bin"
    if not path_now:find(bin, 1, true) then pcall(hl.env, "PATH", bin .. ":" .. path_now) end
    load_stubs()
    load_file(path)

    for _, d in ipairs(devices) do
        local ok, e = pcall(hl.device, d.spec)
        if not ok then problem(d.where, "device " .. tostring(d.spec.name) .. ": " .. tostring(e)) end
    end

    -- the files read this time, for bin/hyprlang-watch (reloads Hyprland when one of them is saved)
    local list = io.open(HOME .. "/.cache/hyprlang-files.txt", "w")
    if list then
        for f in pairs(loaded) do list:write(f, "\n") end
        list:close()
    end
    exec_once[#exec_once + 1] = HOME .. "/.config/hypr/bin/hyprlang-watch"

    if #exec_once > 0 then
        local cmds = exec_once
        hl.on("hyprland.start", function()
            for _, c in ipairs(cmds) do pcall(hl.exec_cmd, c) end
        end)
    end
    if #exec_shutdown > 0 then
        local cmds = exec_shutdown
        hl.on("hyprland.shutdown", function()
            for _, c in ipairs(cmds) do pcall(hl.exec_cmd, c) end
        end)
    end

    local log = io.open(LOG, "w")
    if log then
        log:write(os.date("%Y-%m-%d %H:%M:%S"), "  Hyprland ", (hl.version and hl.version() or "?"), "\n")
        log:write(string.format("files %d, binds %d, rules %d, options %d, autostart %d, other %d\n",
            stats.files, stats.binds, stats.rules, stats.options, stats.execs, stats.other))
        log:write(#problems == 0 and "no problems\n" or (#problems .. " problem(s):\n"))
        for _, p in ipairs(problems) do log:write("  ", p, "\n") end
        log:close()
    end

    if #problems > 0 then
        if os.getenv("HYPRLANG_STRICT") == "1" then
            error(#problems .. " problem(s):\n" .. table.concat(problems, "\n"))
        end
        pcall(function()
            hl.notification.create({
                text = "Config: " .. #problems .. " line(s) could not be applied. Details: ~/.cache/hyprlang-compat.log",
                timeout = 10000, color = "rgba(f38ba8ff)",
            })
        end)
    end
    return stats, problems
end

return M

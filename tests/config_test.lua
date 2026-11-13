-- Tests for file_picker/config.lua. Run from anywhere: rex do path/to/config_test.lua

local dir = (debug.getinfo(1, "S").source:match("^@?(.*[/\\])")) or "./"
local T = dofile(dir .. "helper.lua")
local config = require "file_picker.config"

-- Defaults
local cfg = config.build({})
T.eq("default root is pwd", cfg.roots[1].kind, "pwd")
T.eq("one default root", #cfg.roots, 1)
T.eq("default mode", cfg.mode, "files")
T.eq("pwd style relative", cfg.path_style.pwd, "relative")
T.eq("other style absolute", cfg.path_style.other, "absolute")
T.eq("zoxide style absolute", cfg.path_style.zoxide, "absolute")
T.eq("hidden off", cfg.hidden, false)
T.eq("ignore on", cfg.ignore, true)
T.eq("insert key", cfg.keys.insert[1], "enter")
T.eq("copy key", cfg.keys.copy[1], "ctrl-y")
T.eq("copy absolute key", cfg.keys.copy_absolute[1], "alt-a")
T.eq("copy relative key", cfg.keys.copy_relative[1], "alt-r")
T.eq("insert absolute key", cfg.keys.insert_absolute[1], "alt-A")
T.eq("insert relative key", cfg.keys.insert_relative[1], "alt-R")
T.eq("close esc", cfg.keys.close[1], "esc")
T.eq("close ctrl-g", cfg.keys.close[2], "ctrl-g")
T.eq("down arrow", cfg.keys.down[1], "down")
T.eq("down emacs", cfg.keys.down[2], "ctrl-n")
T.eq("up emacs", cfg.keys.up[2], "ctrl-p")
T.eq("page down emacs", cfg.keys.page_down[2], "ctrl-v")
T.eq("page up emacs", cfg.keys.page_up[2], "alt-v")
T.eq("first emacs", cfg.keys.first[2], "alt-<")
T.eq("last emacs", cfg.keys.last[2], "alt->")
T.eq("dirs toggle", cfg.keys.toggle_dirs[1], "ctrl-t")
T.eq("zoxide toggle", cfg.keys.toggle_zoxide[1], "ctrl-z")
T.eq("default preview rules", #cfg.preview_rules, #config.DEFAULT_PREVIEW)
T.eq("no profiles", #config.profile_names(cfg), 0)
T.check(
  "mdcat forced to colour and kitty images",
  config.DEFAULT_PREVIEW[2].cmd[1]:find("mdcat --ansi --image-protocol kitty", 1, true) == 1,
  config.DEFAULT_PREVIEW[2].cmd[1]
)
T.check(
  "mdcat falls back without --image-protocol",
  config.DEFAULT_PREVIEW[2].cmd[1]:find("|| mdcat --ansi --columns", 1, true) ~= nil
)
local md_cmds = config.DEFAULT_PREVIEW[2].cmd
T.eq("glow after mdcat, no --style", md_cmds[2], 'glow -w "$FZF_PREVIEW_COLUMNS" "$1"')
T.check("bat after glow", md_cmds[3]:find("bat ", 1, true) == 1, md_cmds[3])

-- Default keys leave fzf's Emacs line editing alone
local editing =
  { ["ctrl-a"] = 1, ["ctrl-e"] = 1, ["ctrl-b"] = 1, ["ctrl-f"] = 1, ["ctrl-d"] = 1, ["ctrl-k"] = 1, ["ctrl-w"] = 1 }
for action, keys in pairs(cfg.keys) do
  for _, k in ipairs(keys) do
    T.check("default " .. action .. " key " .. k .. " is not a line editing key", not editing[k])
  end
end

-- Overrides
local c2 = config.build({ keys = { insert = "ctrl-i", down = { "ctrl-j" } } })
T.eq("insert remapped", c2.keys.insert[1], "ctrl-i")
T.eq("insert replaced whole list", #c2.keys.insert, 1)
T.eq("down replaced", c2.keys.down[1], "ctrl-j")
T.eq("down list length", #c2.keys.down, 1)
T.eq("copy kept", c2.keys.copy[1], "ctrl-y")
local c3 = config.build({ path_style = { other = "relative" } })
T.eq("path_style other overridden", c3.path_style.other, "relative")
T.eq("path_style pwd kept", c3.path_style.pwd, "relative")
local c4 = config.build({ preview_extra = { { match = "*.json", cmd = 'jq -C . "$1"' } } })
T.eq("preview_extra first", c4.preview_rules[1].match, "*.json")
T.eq("defaults after extra", #c4.preview_rules, #config.DEFAULT_PREVIEW + 1)
local c5 = config.build({ preview = { { match = "*", cmd = 'cat "$1"' } } })
T.eq("preview replaced", #c5.preview_rules, 1)
local c6 = config.build({ roots = {} })
T.eq("empty roots allowed", #c6.roots, 0)

-- Validation
T.raises("unknown option", function()
  config.build({ root = {} })
end, "unknown option 'root'")
T.raises("unknown key action", function()
  config.build({ keys = { open = "x" } })
end, "unknown action 'open'")
T.raises("bad key type", function()
  config.build({ keys = { insert = 3 } })
end, "keys.insert")
T.raises("root unknown field", function()
  config.build({ roots = { { path = "~", lable = "x" } } })
end, "roots[1]: unknown field 'lable'")
T.raises("root needs one source", function()
  config.build({ roots = { { label = "x" } } })
end, "exactly one of")
T.raises("root two sources", function()
  config.build({ roots = { { path = "~", cmd = "x" } } })
end, "exactly one of")
T.raises("root kind", function()
  config.build({ roots = { { kind = "git" } } })
end, "kind must be")
T.raises("root path type", function()
  config.build({ roots = { { path = 3 } } })
end, "string or a function")
T.raises("root style", function()
  config.build({ roots = { { path = "~", path_style = "rel" } } })
end, "path_style")
T.raises("root tab", function()
  config.build({ roots = { { path = "a\tb" } } })
end, "tabs or newlines")
T.raises("mode", function()
  config.build({ mode = "zoxide" })
end, "mode must be")
T.raises("preview field", function()
  config.build({ preview = { { match = "*", run = "x" } } })
end, "unknown field 'run'")
T.raises("preview needs cmd", function()
  config.build({ preview = { { match = "*" } } })
end, "preview[1].cmd")
T.raises("path_style field", function()
  config.build({ path_style = { git = "relative" } })
end, "unknown field 'git'")
T.raises("hidden type", function()
  config.build({ hidden = "yes" })
end, "hidden must be")
T.raises("profile name", function()
  config.build({ profiles = { ["a-b"] = {} } })
end, "letters, digits or _")
T.raises("profile field", function()
  config.build({ profiles = { a = { profiles = {} } } })
end, "profiles.a: unknown field 'profiles'")
T.raises("profile bad value", function()
  config.build({ profiles = { a = { mode = "x" } } })
end, "profiles.a: mode must be")

-- Function roots are accepted
local function tmp_path()
  return "/tmp"
end
local function true_cmd()
  return "true"
end
local fc = config.build({ roots = { { path = tmp_path }, { cmd = true_cmd } } })
T.eq("function roots kept", #fc.roots, 2)

-- Profiles
local pc = config.build({
  hidden = true,
  keys = { copy = "ctrl-k" },
  profiles = {
    dirs = { mode = "dirs" },
    notes = { roots = { { path = "~/notes" } }, keys = { insert = "ctrl-i" }, title = "Notes" },
  },
})
local names = config.profile_names(pc)
T.eq("profile names sorted 1", names[1], "dirs")
T.eq("profile names sorted 2", names[2], "notes")
local dirs = config.for_profile(pc, "dirs")
T.eq("profile mode", dirs.mode, "dirs")
T.eq("profile inherits roots", dirs.roots[1].kind, "pwd")
T.eq("profile inherits hidden", dirs.hidden, true)
local notes = config.for_profile(pc, "notes")
T.eq("profile roots", notes.roots[1].path, "~/notes")
T.eq("profile key merged", notes.keys.insert[1], "ctrl-i")
T.eq("profile inherits top key", notes.keys.copy[1], "ctrl-k")
T.eq("profile title", notes.title, "Notes")
T.raises("missing profile", function()
  config.for_profile(pc, "nope")
end, "no profile 'nope'")

return T.finish("config")

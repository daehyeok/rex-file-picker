-- Tests for file_picker/picker.lua and the actions in file_picker/init.lua,
-- against a stub `rex`. Run from anywhere: rex do path/to/picker_test.lua

local dir = (debug.getinfo(1, "S").source:match("^@?(.*[/\\])")) or "./"
local T = dofile(dir .. "helper.lua")

-- A stub rex that records actions, binds, layers and calls.
local real_rex = rex
local calls = { actions = {}, binds = 0, layers = {}, remote_layers = {} }
local process_result = { foreground = { cwd = "/work/app" }, child = { cwd = "/home/me" } }
local local_layer_ok = true
rex = {
  action = function(a)
    calls.actions[a.name] = a
  end,
  bind = function()
    calls.binds = calls.binds + 1
  end,
  block = {
    call = function(_, method)
      if method == "process" then
        return process_result
      end
      return nil, "no"
    end,
  },
  session = {
    new_layer = function(req)
      if not local_layer_ok then
        return nil, "not found"
      end
      calls.layers[#calls.layers + 1] = req
      return { layer_id = "layer:1", block_ids = { "block:9" } }
    end,
  },
  server = function()
    return {
      block = {
        call = function()
          return nil, "no"
        end,
      },
      session = {
        new_layer = function(req)
          calls.remote_layers[#calls.remote_layers + 1] = req
          return { layer_id = "layer:2" }
        end,
      },
    }
  end,
}

local config = require "file_picker.config"
local picker = require "file_picker.picker"
local fp = require "file_picker"

-- hint and binds
local cfg = config.build({})
T.eq("hint", picker.hint(cfg), "enter insert  ctrl-y copy  ctrl-t dirs  ctrl-z zoxide  ctrl-/ preview  esc close")
local binds = picker.binds(cfg)
T.check("binds insert", binds:find("enter\tinsert", 1, true) ~= nil, binds)
T.check("binds emacs down", binds:find("ctrl-n\tdown", 1, true) ~= nil, binds)
T.check("binds emacs quit", binds:find("ctrl-g\tclose", 1, true) ~= nil, binds)
T.check("binds page", binds:find("alt-v\tpage_up", 1, true) ~= nil, binds)
T.check("binds copy absolute", binds:find("alt-a\tcopy_absolute", 1, true) ~= nil, binds)
T.check("binds copy relative", binds:find("alt-r\tcopy_relative", 1, true) ~= nil, binds)
T.check("binds insert absolute", binds:find("alt-A\tinsert_absolute", 1, true) ~= nil, binds)
T.check("binds insert relative", binds:find("alt-R\tinsert_relative", 1, true) ~= nil, binds)
local c2 = config.build({ keys = { insert = "ctrl-i" } })
T.check("remapped insert", picker.binds(c2):find("ctrl-i\tinsert", 1, true) ~= nil)
T.check("enter no longer inserts", picker.binds(c2):find("enter\tinsert", 1, true) == nil)

-- rules argv
local r = picker.rules_argv(
  config.build({ preview = { { match = { "*.md", "*.markdown" }, cmd = { 'mdcat "$1"', 'cat "$1"' } } } })
)
T.eq("rules count", r[1], "1")
T.eq("rules matches joined", r[2], "*.md\030*.markdown")
T.eq("rules cmds joined", r[3], 'mdcat "$1"\030cat "$1"')

-- request layout
local share = { picker = "P", list = "L", preview = "V", done = "D", message = "M" }
local req = picker.request({ session_id = "s", block_id = "b" }, cfg, share, "files", "/work", {
  { kind = "pwd", value = "", label = "", style = "relative", hidden = "0", ignore = "1", exclude = "" },
})
local argv = req.layout.block.options.command
T.eq("argv sh", argv[1], "sh")
T.eq("argv script", argv[3], "P")
T.eq("argv origin", argv[5], "b")
T.eq("argv pane dir", argv[6], "/work")
T.eq("argv list", argv[8], "L")
T.eq("argv mode", argv[11], "files")
T.eq("argv copy_cmd empty", argv[14], "")
T.eq("argv zoxide style", argv[15], "absolute")
T.eq("argv preview window", argv[16], "right,55%")
T.eq("argv rule count", argv[18], tostring(#config.DEFAULT_PREVIEW))
local nr = #config.DEFAULT_PREVIEW
T.eq("argv first root kind", argv[18 + 2 * nr + 1], "pwd")
T.eq("argv total", #argv, 18 + 2 * nr + 7)
T.eq("request focuses", req.focus, true)
T.eq("request reads the interactive startup files", req.layout.block.options.interactive, true)
local plain = picker.request(
  { session_id = "s", block_id = "b" },
  config.build({ interactive_shell = false }),
  share,
  "files",
  "/work",
  {}
)
T.eq("interactive_shell = false", plain.layout.block.options.interactive, false)
T.eq("request bounds", req.bounds, cfg.pane_bounds)

-- setup registers actions and binds nothing
local full = fp.setup({ profiles = { dirs = { mode = "dirs" }, notes = { roots = { { path = "~/notes" } } } } })
T.check("pick_file registered", calls.actions.pick_file ~= nil)
T.check("pick_zoxide_dir registered", calls.actions.pick_zoxide_dir ~= nil)
T.check("profile dirs registered", calls.actions.pick_file_dirs ~= nil)
T.check("profile notes registered", calls.actions.pick_file_notes ~= nil)
T.eq("no binds", calls.binds, 0)
T.eq("setup returns cfg", full.mode, "files")

-- running the actions opens a layer with the pane's directory and mode
calls.actions.pick_file.run({ session_id = "s", block_id = "b" })
local a = calls.layers[#calls.layers].layout.block.options.command
T.eq("pick_file pane dir from foreground", a[6], "/work/app")
T.eq("pick_file mode", a[11], "files")
T.check("pick_file script loaded", a[3]:find("picker.sh", 1, true) ~= nil)
calls.actions.pick_file_dirs.run({ session_id = "s", block_id = "b" })
T.eq("profile mode dirs", calls.layers[#calls.layers].layout.block.options.command[11], "dirs")
calls.actions.pick_zoxide_dir.run({ session_id = "s", block_id = "b" })
local z = calls.layers[#calls.layers].layout.block.options.command
T.eq("zoxide mode", z[11], "zoxide")
T.eq("zoxide has no roots", #z, 18 + 2 * nr)

-- shell cwd when there is no foreground cwd
process_result = { child = { cwd = "/home/me" } }
calls.actions.pick_file.run({ session_id = "s", block_id = "b" })
T.eq("child cwd fallback", calls.layers[#calls.layers].layout.block.options.command[6], "/home/me")

-- a remote pane's layer goes to its server when the local server says no
local_layer_ok = false
calls.actions.pick_file.run({ session_id = "s", block_id = "b", server = "devbox" })
T.eq("remote layer", #calls.remote_layers, 1)

rex = real_rex
return T.finish("picker")

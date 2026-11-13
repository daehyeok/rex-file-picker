-- Tests for file_picker/roots.lua. Run from anywhere: rex do path/to/roots_test.lua

local dir = (debug.getinfo(1, "S").source:match("^@?(.*[/\\])")) or "./"
local T = dofile(dir .. "helper.lua")
local config = require "file_picker.config"
local roots = require "file_picker.roots"

local pctx = { host = "devbox", server = "devbox", pwd = "/home/me/src/app" }

-- Default: the pane's directory only
local recs = roots.resolve(config.build({}), pctx)
T.eq("one record", #recs, 1)
T.eq("pwd kind", recs[1].kind, "pwd")
T.eq("pwd value empty", recs[1].value, "")
T.eq("pwd style", recs[1].style, "relative")
T.eq("pwd hidden", recs[1].hidden, "0")
T.eq("pwd ignore", recs[1].ignore, "1")
T.eq("pwd exclude", recs[1].exclude, "")

-- Mixed roots, in order, with per-root overrides
local cfg = config.build({
  hidden = true,
  exclude = { "node_modules" },
  roots = {
    { kind = "pwd" },
    { label = "git", cmd = "git rev-parse --show-toplevel", path_style = "relative" },
    { label = "notes", path = "~/notes", ignore = false, exclude = { "*.tmp", "build" } },
  },
})
recs = roots.resolve(cfg, pctx)
T.eq("three records", #recs, 3)
T.eq("order 1", recs[1].kind, "pwd")
T.eq("order 2", recs[2].kind, "cmd")
T.eq("order 3", recs[3].kind, "path")
T.eq("cmd value", recs[2].value, "git rev-parse --show-toplevel")
T.eq("cmd label", recs[2].label, "git")
T.eq("cmd style override", recs[2].style, "relative")
T.eq("path style default absolute", recs[3].style, "absolute")
T.eq("hidden from top", recs[2].hidden, "1")
T.eq("ignore override", recs[3].ignore, "0")
T.eq("ignore default", recs[2].ignore, "1")
T.eq("exclude from top", recs[1].exclude, "node_modules")
T.eq("exclude override joined", recs[3].exclude, "*.tmp" .. roots.RS .. "build")

-- External roots only
recs = roots.resolve(config.build({ roots = { { path = "~/notes" } } }), pctx)
T.eq("no pwd root", #recs, 1)
T.eq("only path", recs[1].kind, "path")

-- Lua functions see the pane context; nil skips; lists expand
local seen
cfg = config.build({
  roots = {
    {
      label = "brain",
      path = function(c)
        seen = c
        if c.host == "devbox" then
          return "/data/brain"
        end
      end,
    },
    {
      path = function()
        return nil
      end,
    },
    {
      path = function()
        return { "/a", "/b" }
      end,
      label = "multi",
    },
    {
      cmd = function(c)
        return "ls -d " .. c.pwd
      end,
    },
    {
      path = function()
        error("boom")
      end,
    },
    {
      path = function()
        return "bad\tvalue"
      end,
    },
  },
})
local warnings = {}
roots.warn = function(m)
  warnings[#warnings + 1] = m
end
recs = roots.resolve(cfg, pctx)
T.eq("two warnings", #warnings, 2)
T.check("failing function warned", (warnings[1] or ""):find("roots[5].path failed", 1, true) ~= nil, warnings[1])
T.check("tab value warned", (warnings[2] or ""):find("tabs or newlines", 1, true) ~= nil, warnings[2])
T.eq("function got context", seen and seen.pwd, "/home/me/src/app")
T.eq("records from functions", #recs, 4)
T.eq("host-chosen path", recs[1].value, "/data/brain")
T.eq("list expands 1", recs[2].value, "/a")
T.eq("list expands 2", recs[3].value, "/b")
T.eq("list keeps label", recs[3].label, "multi")
T.eq("cmd function", recs[4].value, "ls -d /home/me/src/app")
T.eq("cmd function kind", recs[4].kind, "cmd")
recs = roots.resolve(cfg, { host = "other", pwd = "/x" })
roots.warn = function() end
T.eq("other host skips brain", recs[1].value, "/a")

-- argv: 7 fields per root
local argv =
  roots.argv(roots.resolve(config.build({ roots = { { kind = "pwd" }, { path = "/n", label = "n" } } }), pctx))
T.eq("argv length", #argv, 14)
T.eq("argv kind", argv[1], "pwd")
T.eq("argv second root", argv[8], "path")
T.eq("argv value", argv[9], "/n")
T.eq("argv label", argv[10], "n")
T.eq("argv style", argv[11], "absolute")

return T.finish("roots")

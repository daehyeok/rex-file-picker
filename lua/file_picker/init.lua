-- file_picker: pick files from the focused pane's directory and other roots
-- in a floating fzf pane, then insert or copy their paths.
--
-- setup(opts) validates the options and registers the actions:
--   pick_file          files under the configured roots
--   pick_zoxide_dir    zoxide's directories, most frecent first
--   pick_file_<name>   one per entry in `profiles`
-- It binds no keys; bind them with rex.bind.

local config = require "file_picker.config"
local message = require "file_picker.message"
local picker = require "file_picker.picker"
local rexapi = require "file_picker.rexapi"
local roots = require "file_picker.roots"

local M = {}

-- The plugin's root directory (with a trailing slash), from this file's path.
local ROOT = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*/)lua/file_picker/[^/]*$")) or "./"

local function read_file(path)
  local f, err = io.open(path, "r")
  if not f then
    return nil, err
  end
  local s = f:read("*a")
  f:close()
  return s
end

-- Loads the shell scripts the panes run, once.
local share
local function load_share()
  if share then
    return share
  end
  local s = {}
  for _, name in ipairs({ "picker", "list", "preview", "done", "message" }) do
    local text, err = read_file(ROOT .. "share/" .. name .. ".sh")
    if not text then
      return nil, err
    end
    s[name] = text
  end
  share = s
  return share
end

-- Shows msg in a message pane; falls back to the Rex log if even that fails.
local function say(ctx, msg)
  local s, err = load_share()
  local ok = false
  if s then
    ok, err = message.show(ctx, msg, s.message)
  end
  if not ok then
    io.stderr:write("rex-file-picker: " .. msg .. " (" .. tostring(err) .. ")\n")
  end
end

-- Opens the picker over ctx's pane with cfg, starting in `mode`.
function M.pick(ctx, cfg, mode)
  local s, err = load_share()
  if not s then
    return say(ctx, "Can't read the picker scripts: " .. tostring(err))
  end
  local dir = rexapi.pane_dir(ctx)
  local pctx = {
    host = ctx.server or "local",
    server = ctx.server,
    pwd = dir,
    session_id = ctx.session_id,
    block_id = ctx.block_id,
  }
  local records = {}
  if mode ~= "zoxide" then
    records = roots.resolve(cfg, pctx)
    if #records == 0 then
      return say(ctx, "Nothing to search: no root applies here")
    end
  end
  local res, _, lerr = rexapi.new_layer(ctx, picker.request(ctx, cfg, s, mode, dir, records))
  if not res then
    say(ctx, "Can't show the file picker: " .. tostring(lerr))
  end
end

-- Validates opts and registers the actions. Binds no keys. Errors name any
-- unknown or invalid option.
function M.setup(opts)
  local cfg = config.build(opts)
  rex.action {
    name = "pick_file",
    title = cfg.title or "Pick a File",
    description = "Fuzzy-pick files under the focused pane's directory and other roots, then insert or copy their paths.",
    run = function(ctx)
      M.pick(ctx, cfg, cfg.mode)
    end,
  }
  rex.action {
    name = "pick_zoxide_dir",
    title = "Pick a Zoxide Directory",
    description = "Fuzzy-pick one of zoxide's directories, then insert or copy its path.",
    run = function(ctx)
      M.pick(ctx, cfg, "zoxide")
    end,
  }
  for _, name in ipairs(config.profile_names(cfg)) do
    local pcfg = config.for_profile(cfg, name)
    rex.action {
      name = "pick_file_" .. name,
      title = cfg.profiles[name].title or ("Pick a File (" .. name .. ")"),
      description = "Fuzzy-pick files with the '" .. name .. "' profile, then insert or copy their paths.",
      run = function(ctx)
        M.pick(ctx, pcfg, pcfg.mode)
      end,
    }
  end
  return cfg
end

return M

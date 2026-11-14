-- file_picker/picker.lua: builds the floating picker pane.
--
-- Runs in the Rex config on the client. The pane runs share/picker.sh on the
-- host of the pane the user is in; everything it needs (helper scripts,
-- keys, preview rules, roots) travels as arguments, because the client can't
-- write files on a remote host.

local rexapi = require "file_picker.rexapi"
local roots = require "file_picker.roots"

local M = {}

M.LABEL = "file-picker"

-- fzf names for the hint.
local HINT_ACTIONS = {
  { "insert", "insert" },
  { "copy", "copy" },
  { "toggle_dirs", "dirs" },
  { "toggle_zoxide", "zoxide" },
  { "toggle_preview", "preview" },
  { "close", "close" },
}

-- The key hint shown in the header, from the first key of each action.
function M.hint(cfg)
  local parts = {}
  for _, a in ipairs(HINT_ACTIONS) do
    local k = cfg.keys[a[1]] and cfg.keys[a[1]][1]
    if k then
      parts[#parts + 1] = k .. " " .. a[2]
    end
  end
  return table.concat(parts, "  ")
end

-- The "KEY<TAB>ACTION" lines picker.sh turns into fzf --bind flags.
function M.binds(cfg)
  local lines = {}
  for _, action in ipairs(require("file_picker.config").KEY_ACTIONS) do
    for _, key in ipairs(cfg.keys[action] or {}) do
      lines[#lines + 1] = key .. "\t" .. action
    end
  end
  return table.concat(lines, "\n")
end

local function as_list(v)
  if type(v) == "string" then
    return { v }
  end
  return v
end

-- Returns the preview rules as argv fields: count, then (matches, commands)
-- per rule, each list joined by \036.
function M.rules_argv(cfg)
  local out = { tostring(#cfg.preview_rules) }
  for _, r in ipairs(cfg.preview_rules) do
    out[#out + 1] = table.concat(as_list(r.match), roots.RS)
    out[#out + 1] = table.concat(as_list(r.cmd), roots.RS)
  end
  return out
end

-- Returns the session.new_layer request for the picker over ctx's pane.
-- share = { picker, list, preview, done } script texts; mode = files | dirs |
-- zoxide; pane_dir = the pane's working directory ("" if unknown);
-- records = roots.resolve(...).
function M.request(ctx, cfg, share, mode, pane_dir, records)
  local argv = {
    "sh",
    "-c",
    share.picker,
    M.LABEL,
    ctx.block_id or "",
    pane_dir or "",
    rexapi.rex_cli(),
    share.list,
    share.preview,
    share.done,
    mode,
    M.binds(cfg),
    cfg.fzf_options or "",
    cfg.copy_cmd or "",
    cfg.path_style.zoxide,
    cfg.preview_window,
    M.hint(cfg),
  }
  for _, f in ipairs(M.rules_argv(cfg)) do
    argv[#argv + 1] = f
  end
  for _, f in ipairs(roots.argv(records)) do
    argv[#argv + 1] = f
  end
  return {
    session_id = ctx.session_id,
    bounds = cfg.pane_bounds,
    focus = true,
    layout = {
      block = {
        flavor = "com.superlogical.terminal.shell",
        label = M.LABEL,
        options = { command = argv, interactive = cfg.interactive_shell },
      },
    },
  }
end

return M

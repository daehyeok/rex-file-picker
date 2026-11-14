-- file_picker/config.lua: options, their defaults, and validation.
--
-- Pure Lua 5.1 with no rex.* calls, so the whole option model is tested
-- without a running session. Every option is optional; an unknown option,
-- root field, preview field, profile field or key action raises an error
-- that names it.

local M = {}

local function fail(fmt, ...)
  error("rex-file-picker: " .. string.format(fmt, ...), 0)
end

-- Picker actions `keys` may bind, in the order the key hint lists them.
M.KEY_ACTIONS = {
  "insert",
  "copy",
  "insert_absolute",
  "insert_relative",
  "copy_absolute",
  "copy_relative",
  "toggle_dirs",
  "toggle_zoxide",
  "toggle_preview",
  "close",
  "up",
  "down",
  "page_up",
  "page_down",
  "first",
  "last",
}

-- Arrow/page keys and Emacs-style keys together. fzf's own line editing
-- keys (ctrl-a/e/b/f/d/k/w) are left alone.
M.DEFAULT_KEYS = {
  insert = { "enter" },
  copy = { "ctrl-y" },
  insert_absolute = { "alt-A" },
  insert_relative = { "alt-R" },
  copy_absolute = { "alt-a" },
  copy_relative = { "alt-r" },
  close = { "esc", "ctrl-g" },
  toggle_zoxide = { "ctrl-z" },
  toggle_dirs = { "ctrl-t" },
  toggle_preview = { "ctrl-/" },
  up = { "up", "ctrl-p" },
  down = { "down", "ctrl-n" },
  page_up = { "page-up", "alt-v" },
  page_down = { "page-down", "ctrl-v" },
  first = { "home", "alt-<" },
  last = { "end", "alt->" },
}

-- Preview commands run on the pane's host with the entry's path as $1 and
-- fzf's FZF_PREVIEW_COLUMNS / FZF_PREVIEW_LINES set. A rule's first command
-- whose first word is installed is used.
local BAT = 'bat --color=always --style=numbers --paging=never --terminal-width="$FZF_PREVIEW_COLUMNS" "$1"'
local BATCAT = 'batcat --color=always --style=numbers --paging=never --terminal-width="$FZF_PREVIEW_COLUMNS" "$1"'
local CAT = 'cat "$1"'
local MDCAT = 'mdcat --ansi --image-protocol kitty --columns "$FZF_PREVIEW_COLUMNS" "$1" 2>/dev/null'
  .. ' || mdcat --ansi --columns "$FZF_PREVIEW_COLUMNS" "$1"'
-- No --style: a user's glow config wins (in a pipe glow's automatic style is plain).
local GLOW = 'glow -w "$FZF_PREVIEW_COLUMNS" "$1"'
M.DEFAULT_PREVIEW = {
  { match = "directory", cmd = { 'tree -C -L 2 "$1"', 'ls -la "$1"' } },
  {
    match = { "*.md", "*.markdown" },
    -- mdcat drops all styling when its output isn't a terminal (fzf's preview
    -- is a pipe): --ansi forces colours, and --image-protocol kitty adds inline
    -- images on top. Older mdcat has no --image-protocol, hence the fallback.
    cmd = { MDCAT, GLOW, BAT, BATCAT, CAT },
  },
  {
    match = { "mime:image/*", "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.bmp" },
    cmd = {
      "kitten icat --clear --transfer-mode=stream --stdin=no --unicode-placeholder"
        .. ' --place="${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0" "$1"',
    },
  },
  { match = "*", cmd = { BAT, BATCAT, CAT } },
}

M.PATH_STYLES = { relative = true, absolute = true }
M.MODES = { files = true, dirs = true }

-- Settings a profile may override (everything but `profiles` itself).
local PROFILE_FIELDS = {
  roots = true,
  mode = true,
  path_style = true,
  hidden = true,
  ignore = true,
  exclude = true,
  preview = true,
  preview_extra = true,
  preview_window = true,
  keys = true,
  copy_cmd = true,
  fzf_options = true,
  pane_bounds = true,
  interactive_shell = true,
  title = true,
}

local ROOT_FIELDS = {
  kind = true,
  path = true,
  cmd = true,
  label = true,
  path_style = true,
  hidden = true,
  ignore = true,
  exclude = true,
}

local function defaults()
  return {
    roots = { { kind = "pwd" } },
    mode = "files",
    path_style = { pwd = "relative", other = "absolute", zoxide = "absolute" },
    hidden = false,
    ignore = true,
    exclude = {},
    preview = M.DEFAULT_PREVIEW,
    preview_extra = {},
    preview_window = "right,55%",
    keys = {},
    copy_cmd = nil,
    fzf_options = "",
    pane_bounds = { 0.05, 0.06, 0.9, 0.88 },
    -- Start picker panes with the user's interactive shell environment
    -- (e.g. ~/.zshrc), so host tools are found on the same PATH as in
    -- their terminals.
    interactive_shell = true,
    title = nil,
    profiles = {},
  }
end

local function is_list_of(v, ty)
  if type(v) ~= "table" then
    return false
  end
  local n = 0
  for _ in pairs(v) do
    n = n + 1
  end
  if n ~= #v then
    return false
  end
  for _, x in ipairs(v) do
    if type(x) ~= ty then
      return false
    end
  end
  return true
end

-- Strings that cross into the host script as one field: no tabs or newlines.
local function one_line(where, s)
  if s:find("[\t\n\r]") then
    fail("%s must not contain tabs or newlines", where)
  end
end

local function check_string_list(where, v)
  if type(v) == "string" then
    v = { v }
  end
  if not is_list_of(v, "string") or #v == 0 then
    fail("%s must be a string or a non-empty list of strings", where)
  end
  for i, s in ipairs(v) do
    one_line(where .. "[" .. i .. "]", s)
  end
end

local function check_bool(where, v)
  if type(v) ~= "boolean" then
    fail("%s must be true or false", where)
  end
end

local function check_exclude(where, v)
  if not is_list_of(v, "string") then
    fail("%s must be a list of strings", where)
  end
  for i, s in ipairs(v) do
    one_line(where .. "[" .. i .. "]", s)
  end
end

local function check_root(i, r)
  local where = "roots[" .. i .. "]"
  if type(r) ~= "table" then
    fail("%s must be a table", where)
  end
  for k in pairs(r) do
    if not ROOT_FIELDS[k] then
      fail("%s: unknown field '%s'", where, tostring(k))
    end
  end
  local n = (r.kind ~= nil and 1 or 0) + (r.path ~= nil and 1 or 0) + (r.cmd ~= nil and 1 or 0)
  if n ~= 1 then
    fail('%s needs exactly one of kind = "pwd", path or cmd', where)
  end
  if r.kind ~= nil and r.kind ~= "pwd" then
    fail('%s.kind must be "pwd"', where)
  end
  for _, f in ipairs({ "path", "cmd" }) do
    local v = r[f]
    if v ~= nil then
      if type(v) == "string" then
        if v == "" then
          fail("%s.%s must not be empty", where, f)
        end
        one_line(where .. "." .. f, v)
      elseif type(v) ~= "function" then
        fail("%s.%s must be a string or a function", where, f)
      end
    end
  end
  if r.label ~= nil then
    if type(r.label) ~= "string" then
      fail("%s.label must be a string", where)
    end
    one_line(where .. ".label", r.label)
  end
  if r.path_style ~= nil and not M.PATH_STYLES[r.path_style] then
    fail('%s.path_style must be "relative" or "absolute"', where)
  end
  if r.hidden ~= nil then
    check_bool(where .. ".hidden", r.hidden)
  end
  if r.ignore ~= nil then
    check_bool(where .. ".ignore", r.ignore)
  end
  if r.exclude ~= nil then
    check_exclude(where .. ".exclude", r.exclude)
  end
end

local function check_preview(name, v)
  if type(v) ~= "table" then
    fail("%s must be a list of rules", name)
  end
  for i, rule in ipairs(v) do
    local where = name .. "[" .. i .. "]"
    if type(rule) ~= "table" then
      fail("%s must be a table", where)
    end
    for k in pairs(rule) do
      if k ~= "match" and k ~= "cmd" then
        fail("%s: unknown field '%s'", where, tostring(k))
      end
    end
    check_string_list(where .. ".match", rule.match)
    check_string_list(where .. ".cmd", rule.cmd)
  end
end

local CHECKS
CHECKS = {
  roots = function(v)
    if type(v) ~= "table" then
      fail("roots must be a list")
    end
    for i, r in ipairs(v) do
      check_root(i, r)
    end
  end,
  mode = function(v)
    if not M.MODES[v] then
      fail('mode must be "files" or "dirs"')
    end
  end,
  path_style = function(v)
    if type(v) ~= "table" then
      fail("path_style must be a table")
    end
    for k, s in pairs(v) do
      if k ~= "pwd" and k ~= "other" and k ~= "zoxide" then
        fail("path_style: unknown field '%s'", tostring(k))
      end
      if not M.PATH_STYLES[s] then
        fail('path_style.%s must be "relative" or "absolute"', k)
      end
    end
  end,
  hidden = function(v)
    check_bool("hidden", v)
  end,
  ignore = function(v)
    check_bool("ignore", v)
  end,
  exclude = function(v)
    check_exclude("exclude", v)
  end,
  preview = function(v)
    check_preview("preview", v)
  end,
  preview_extra = function(v)
    check_preview("preview_extra", v)
  end,
  preview_window = function(v)
    if type(v) ~= "string" or v == "" then
      fail("preview_window must be a non-empty string")
    end
    one_line("preview_window", v)
  end,
  keys = function(v)
    if type(v) ~= "table" then
      fail("keys must be a table")
    end
    for k, keys in pairs(v) do
      if M.DEFAULT_KEYS[k] == nil then
        fail("keys: unknown action '%s'", tostring(k))
      end
      check_string_list("keys." .. k, keys)
    end
  end,
  copy_cmd = function(v)
    if type(v) ~= "string" or v == "" then
      fail("copy_cmd must be a non-empty string")
    end
    one_line("copy_cmd", v)
  end,
  fzf_options = function(v)
    if type(v) ~= "string" then
      fail("fzf_options must be a string")
    end
    one_line("fzf_options", v)
  end,
  pane_bounds = function(v)
    if not is_list_of(v, "number") or #v ~= 4 then
      fail("pane_bounds must be four numbers { x, y, width, height }")
    end
  end,
  interactive_shell = function(v)
    check_bool("interactive_shell", v)
  end,
  title = function(v)
    if type(v) ~= "string" or v == "" then
      fail("title must be a non-empty string")
    end
  end,
  profiles = function(v)
    if type(v) ~= "table" then
      fail("profiles must be a table")
    end
    for name, p in pairs(v) do
      if type(name) ~= "string" or not name:match("^[%w_]+$") then
        fail("profiles: name '%s' must be letters, digits or _", tostring(name))
      end
      if type(p) ~= "table" then
        fail("profiles.%s must be a table", name)
      end
      for k, pv in pairs(p) do
        if not PROFILE_FIELDS[k] then
          fail("profiles.%s: unknown field '%s'", name, tostring(k))
        end
        local ok, err = pcall(CHECKS[k], pv)
        if not ok then
          fail("profiles.%s: %s", name, (tostring(err):gsub("^rex%-file%-picker: ", "")))
        end
      end
    end
  end,
}

local function as_list(v)
  if type(v) == "string" then
    return { v }
  end
  return v
end

-- Fills in path_style defaults and per-action key lists. An action set in
-- `keys` replaces that action's whole default list.
local function finish(cfg)
  local ps = defaults().path_style
  for k, v in pairs(cfg.path_style or {}) do
    ps[k] = v
  end
  cfg.path_style = ps
  local keys = {}
  for action, list in pairs(M.DEFAULT_KEYS) do
    keys[action] = as_list(cfg.keys[action] or list)
  end
  cfg.keys = keys
  local rules = {}
  for _, r in ipairs(cfg.preview_extra or {}) do
    rules[#rules + 1] = r
  end
  for _, r in ipairs(cfg.preview or {}) do
    rules[#rules + 1] = r
  end
  cfg.preview_rules = rules
  return cfg
end

-- Validates opts and returns the full top-level config (defaults filled in).
function M.build(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    fail("setup expects a table of options")
  end
  for k in pairs(opts) do
    if not CHECKS[k] then
      fail("unknown option '%s'", tostring(k))
    end
  end
  local cfg = defaults()
  for k, v in pairs(opts) do
    CHECKS[k](v)
    cfg[k] = v
  end
  cfg.raw = opts
  return finish(cfg)
end

-- Returns the config for profile `name`: the top-level options with the
-- profile's settings on top (keys merge per action, path_style per field).
function M.for_profile(cfg, name)
  local p = cfg.profiles[name]
  if not p then
    fail("no profile '%s'", tostring(name))
  end
  local merged = {}
  for k, v in pairs(cfg.raw) do
    if k ~= "profiles" then
      merged[k] = v
    end
  end
  for k, v in pairs(p) do
    if k == "keys" or k == "path_style" then
      local t = {}
      for kk, vv in pairs(merged[k] or {}) do
        t[kk] = vv
      end
      for kk, vv in pairs(v) do
        t[kk] = vv
      end
      merged[k] = t
    else
      merged[k] = v
    end
  end
  return M.build(merged)
end

-- Returns the profile names in sorted order.
function M.profile_names(cfg)
  local names = {}
  for name in pairs(cfg.profiles) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

return M

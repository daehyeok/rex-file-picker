-- file_picker/roots.lua: turns the `roots` option into the records the host
-- script resolves.
--
-- Runs in the Rex config on the client. Lua functions (path = fn, cmd = fn)
-- are called here, with the pane context, so they can choose by host or
-- build from the pane's directory, but can't look at a remote host's disk.
-- Commands run later, on the pane's host, in the pane's directory.

local M = {}

M.RS = "\030" -- separates a root's exclude patterns inside one field (\036)

-- Where warnings about skipped roots go (replaceable, e.g. by tests).
function M.warn(msg)
  io.stderr:write("rex-file-picker: " .. msg .. "\n")
end
local function warn(msg)
  M.warn(msg)
end

local function bool(v)
  return v and "1" or "0"
end

-- The root's own setting, else the top-level one.
local function pick(own, top)
  if own == nil then
    return top
  end
  return own
end

local function usable(where, s)
  if type(s) ~= "string" or s == "" then
    return false
  end
  if s:find("[\t\n\r]") then
    warn(where .. " returned a value with tabs or newlines; skipped")
    return false
  end
  return true
end

-- Returns the list of root records for cfg in pctx, where pctx is
-- { host, server, pwd, session_id, block_id }. Each record is
-- { kind = "pwd"|"path"|"cmd", value, label, style, hidden, ignore, exclude }
-- with every field a string. Roots whose function returns nil (or fails) are
-- left out.
function M.resolve(cfg, pctx)
  local out = {}
  for i, r in ipairs(cfg.roots) do
    local where = "roots[" .. i .. "]"
    local is_pwd = r.kind == "pwd"
    local base = {
      label = r.label or "",
      style = r.path_style or (is_pwd and cfg.path_style.pwd or cfg.path_style.other),
      hidden = bool(pick(r.hidden, cfg.hidden)),
      ignore = bool(pick(r.ignore, cfg.ignore)),
      exclude = table.concat(pick(r.exclude, cfg.exclude), M.RS),
    }
    local function add(kind, value)
      local rec = { kind = kind, value = value }
      for k, v in pairs(base) do
        rec[k] = v
      end
      out[#out + 1] = rec
    end
    if is_pwd then
      add("pwd", "")
    else
      local kind = r.path ~= nil and "path" or "cmd"
      local v = r[kind]
      if type(v) == "function" then
        local ok, res = pcall(v, pctx)
        if not ok then
          warn(where .. "." .. kind .. " failed: " .. tostring(res))
          res = nil
        end
        v = res
      end
      if kind == "path" and type(v) == "table" then
        for j, p in ipairs(v) do
          if usable(where .. ".path[" .. j .. "]", p) then
            add("path", p)
          end
        end
      elseif usable(where .. "." .. kind, v) then
        add(kind, v)
      end
    end
  end
  return out
end

-- Returns the records as a flat argv list, 7 fields per root, in the order
-- the host script reads them.
function M.argv(records)
  local argv = {}
  for _, r in ipairs(records) do
    for _, f in ipairs({ r.kind, r.value, r.label, r.style, r.hidden, r.ignore, r.exclude }) do
      argv[#argv + 1] = f
    end
  end
  return argv
end

return M

-- file_picker/rexapi.lua: the few Rex calls the plugin needs, with the
-- remote-server fallback.
--
-- Runs in the Rex config (init.lua) on the client. A pane on a remote host
-- belongs to that host's Rex server: calls about it go first to the local
-- server, and when that finds nothing, to rex.server(ctx.server).

local M = {}

M.TERMINAL = "com.superlogical.terminal"

-- Where the Rex app keeps its CLI on macOS.
local MAC_REX_CLI = (os.getenv("HOME") or "")
  .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"

local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end
M.file_exists = file_exists

-- Returns the path of the client's rex CLI: $REX_BIN_DIR/rex, then the macOS
-- app bundle, then plain "rex" from PATH.
function M.rex_cli()
  local bin = os.getenv("REX_BIN_DIR")
  if bin and bin ~= "" and file_exists(bin .. "/rex") then
    return bin .. "/rex"
  end
  if file_exists(MAC_REX_CLI) then
    return MAC_REX_CLI
  end
  return "rex"
end

-- Attaches the calling stream to a session. Calls made outside a key press
-- (e.g. an action run with `rex do`) start without one.
local function attach(api, session_id)
  if session_id and api.session and type(api.session.attach) == "function" then
    pcall(api.session.attach, { session_id = session_id })
  end
end

-- Calls a terminal method on ctx's block, on whichever server owns it.
-- Returns the result, or nil and an error.
function M.terminal_call(ctx, method, extra)
  local args = { block_id = ctx.block_id, session_id = ctx.session_id }
  for k, v in pairs(extra or {}) do
    args[k] = v
  end
  local r, err = rex.block.call(M.TERMINAL, method, args)
  if r ~= nil then
    return r, err
  end
  if tostring(err):find("not attached", 1, true) then
    attach(rex, ctx.session_id)
    r, err = rex.block.call(M.TERMINAL, method, args)
    if r ~= nil then
      return r, err
    end
  end
  if not ctx.server then
    return r, err
  end
  local srv = rex.server(ctx.server)
  r, err = srv.block.call(M.TERMINAL, method, args)
  if r ~= nil then
    return r, err
  end
  -- A server we haven't attached to yet doesn't know the session.
  attach(srv, ctx.session_id)
  return srv.block.call(M.TERMINAL, method, args)
end

-- Returns the working directory of the program in ctx's pane (the
-- foreground program, else the pane's shell), or "" when unknown. The host
-- script falls back to $HOME.
function M.pane_dir(ctx)
  local p = M.terminal_call(ctx, "process")
  if type(p) == "table" then
    for _, k in ipairs({ "foreground", "child" }) do
      local cwd = type(p[k]) == "table" and p[k].cwd
      if type(cwd) == "string" and cwd ~= "" then
        return cwd
      end
    end
  end
  return ""
end

-- Creates a floating layer on the server that owns ctx's pane.
-- Returns the new_layer result ({ block_ids, layer_id, ... }) and the server
-- label it was created on (nil = local), or nil, nil and an error.
function M.new_layer(ctx, req)
  local res, err = rex.session.new_layer(req)
  if res ~= nil and err == nil then
    return res, nil
  end
  if ctx.server then
    res, err = rex.server(ctx.server).session.new_layer(req)
    if res ~= nil and err == nil then
      return res, ctx.server
    end
  end
  return nil, nil, tostring(err)
end

return M

-- file_picker/message.lua: one-line messages in a small floating pane.
--
-- Runs in the Rex config on the client. The pane itself (share/message.sh)
-- runs on the host of the pane the user is in, closes after about a second or
-- on any key, and gives focus back to that pane.

local rexapi = require "file_picker.rexapi"

local M = {}

M.LABEL = "file-picker-message"
-- Centered strip: wide enough for a sentence, a few rows tall.
M.BOUNDS = { 0.25, 0.44, 0.5, 0.08 }

-- Shows msg over ctx's pane. script is the text of share/message.sh.
-- Returns true, or nil and an error.
function M.show(ctx, msg, script)
  local res, _, err = rexapi.new_layer(ctx, {
    session_id = ctx.session_id,
    bounds = M.BOUNDS,
    focus = true,
    layout = {
      block = {
        flavor = "com.superlogical.terminal.shell",
        label = M.LABEL,
        options = { command = { "sh", "-c", script, M.LABEL, msg, ctx.block_id or "", rexapi.rex_cli() } },
      },
    },
  })
  if not res then
    return nil, err
  end
  return true
end

return M

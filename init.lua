-- rex-file-picker entry point for `require("plugins.rex-file-picker")`.
--
-- Clone the repository into the `plugins` folder of your Rex config
-- (~/.config/rex/plugins/rex-file-picker); this file puts the plugin's lua/
-- directory on package.path and returns the file_picker module.

local dir = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/[^/]*$")) or "."
local lua_dir = dir .. "/lua/"
if not package.path:find(lua_dir, 1, true) then
  package.path = lua_dir .. "?.lua;" .. lua_dir .. "?/init.lua;" .. package.path
end
return require("file_picker")

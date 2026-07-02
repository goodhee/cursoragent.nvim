---@mod cursoragent.version Version information for cursoragent.nvim
---@brief [[
--- This module provides version information for cursoragent.nvim.
--- It is the single source of truth for the plugin version.
---@brief ]]

---@class CursorAgentVersion
---@field major number Major version (breaking changes)
---@field minor number Minor version (new features)
---@field patch number Patch version (bug fixes)
local M = {}

-- Individual version components
M.major = 0
M.minor = 2
M.patch = 0

-- Combined semantic version
M.version = string.format("%d.%d.%d", M.major, M.minor, M.patch)

---Returns the formatted version string.
---@return string version Version string in the format "major.minor.patch"
function M.string()
  return M.version
end

---Prints the current version of the plugin.
function M.print_version()
  vim.notify("cursoragent.nvim version: " .. M.string(), vim.log.levels.INFO)
end

return M

local M = {}
local config = require("unipackage.core.config")

--- Checks for package manager files in the current directory
-- @return table: list of detected package managers
function M.get_checks()
    local detected = config.get_detected_managers()
    local all_checks = {}
    
    -- Copy detected managers
    for _, manager in ipairs(detected) do
        table.insert(all_checks, manager)
    end
    
    -- Keep existing checks for compatibility
    local cwd = vim.fn.getcwd()
    if M.file_exists(cwd .. "/package.json") then
        table.insert(all_checks, "package")
    end
    
    if M.file_exists(cwd .. "/.luarc.json") then
        table.insert(all_checks, "luarc")
    end
    
    return all_checks
end

--- Gets the preferred package manager for the current project
-- Lock files take priority over user preference
-- @return string|nil: preferred package manager name
function M.get_preferred_manager()
    return config.get_preferred_manager()
end

--- Gets the package manager to use for project operations
-- Respects lock file priority over user preference
-- @return string|nil: manager name or nil if none available
function M.get_manager_for_project()
    return config.get_preferred_manager()
end

--- Checks if a file exists
-- @param path: file path to check
-- @return boolean: true if file exists
function M.file_exists(path)
    local file = vim.uv.fs_stat(path)
    return file ~= nil
end

--- Gets priority order from configuration
-- @return table: array of package manager names in priority order
function M.get_priority_order()
    return config.get_priority_order()
end

--- Checks if a package manager is available on the system
-- @param manager: package manager name
-- @return boolean: true if manager is available
function M.is_manager_available(manager)
    return config.is_manager_available(manager)
end

--- Gets detected package managers from lock files
-- @return table: array of detected manager names
function M.get_detected_managers()
    return config.get_detected_managers()
end

return M

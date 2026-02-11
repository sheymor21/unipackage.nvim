local M = {}

-- Core modules
local config = require("unipackage.core.config")
local actions = require("unipackage.core.actions")
local ui = require("unipackage.core.ui")
local modules = require("unipackage.core.modules")
local cache = require("unipackage.utils.cache")

--- Setup function for user configuration
-- @param user_config table|nil: User configuration
-- @return boolean: Success status
function M.setup(user_config)
    local ok = config.setup(user_config)
    if ok then
        -- Re-initialize cache with new settings if needed
        cache.init()
    end
    return ok
end

-- Legacy functions for backward compatibility

--- List installed packages
function M.list_packages()
    actions.list_packages()
end

--- Show install packages dialog
function M.install_packages()
    ui.install_packages_dialog()
end

--- Show uninstall packages dialog
function M.uninstall_packages()
    ui.uninstall_packages_dialog()
end

--- Show unified package menu
function M.package_menu()
    ui.package_menu()
end

-- Configuration accessors

--- Get configuration value
-- @param key string|nil: Configuration key or nil for all
-- @return any: Configuration value
function M.get_config(key)
    return config.get(key)
end

--- Get preferred manager
-- @return string|nil: Preferred manager name
function M.get_preferred_manager()
    return config.get_preferred_manager()
end

--- Get detected managers
-- @return table: Array of detected manager names
function M.get_detected_managers()
    return config.get_detected_managers()
end

--- Get detected language
-- @return string|nil: Detected language
function M.get_detected_language()
    return config.detect_language()
end

-- Debug and diagnostics

--- Show debug information
function M.debug()
    local detected = config.get_detected_managers()
    local preferred = config.get_preferred_manager()
    local language = config.detect_language()
    local cwd = vim.fn.getcwd()
    local patterns = config.get_detection_patterns()

    local lines = {
        "UniPackage Debug Info:",
        "",
        "Current directory: " .. cwd,
        "Detected language: " .. (language or "none"),
        "",
        "Detected managers: " .. vim.inspect(detected),
        "",
        "Preferred manager: " .. (preferred or "nil"),
        "",
        "Checking lock files:",
    }

    for manager, files in pairs(patterns) do
        table.insert(lines, "  " .. manager .. ":")
        for _, file in ipairs(files) do
            local exists = vim.fn.filereadable(cwd .. "/" .. file) == 1
            local status = exists and "✓ FOUND" or "✗ not found"
            table.insert(lines, "    " .. file .. ": " .. status)
        end
    end

    -- Add cache stats
    local stats = cache.stats()
    table.insert(lines, "")
    table.insert(lines, "Cache stats:")
    table.insert(lines, "  Entries: " .. stats.entries)
    table.insert(lines, "  Memory: " .. stats.memory .. " bytes")
    table.insert(lines, "  Expired: " .. stats.expired)

    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Clear all caches
function M.clear_cache()
    cache.clear()
    modules.clear_cache()
    config.clear_cache()
    vim.notify("UniPackage: All caches cleared", vim.log.levels.INFO)
end

-- User Commands

vim.api.nvim_create_user_command('UniPackageList', function()
    M.list_packages()
end, { desc = "List packages for detected package manager" })

vim.api.nvim_create_user_command('UniPackageInstall', function()
    M.install_packages()
end, { desc = "Interactive package installation with search" })

vim.api.nvim_create_user_command('UniPackageUninstall', function()
    M.uninstall_packages()
end, { desc = "Interactive package uninstallation" })

vim.api.nvim_create_user_command('UniPackageMenu', function()
    M.package_menu()
end, { desc = "Unified package management menu" })

vim.api.nvim_create_user_command('UniPackageSetup', function(opts)
    if not opts.args or opts.args == "" then
        vim.notify("UniPackage: Current config:\n" .. vim.inspect(config.get()), vim.log.levels.INFO)
        return
    end

    local ok, parsed = pcall(vim.fn.json_decode, opts.args)
    if not ok then
        vim.notify("UniPackage: Invalid JSON configuration", vim.log.levels.ERROR)
        return
    end

    M.setup(parsed)
    vim.notify("UniPackage: Configuration updated", vim.log.levels.INFO)
end, {
    desc = "Configure UniPackage settings",
    nargs = "?",
    complete = function()
        return {
            '{"search_batch_size": 10}',
            '{"package_managers": ["bun", "npm"]}',
            '{"fallback_to_any": false}',
            '{"warn_on_fallback": true}'
        }
    end
})

vim.api.nvim_create_user_command('UniPackageDebug', function()
    M.debug()
end, { desc = "Show UniPackage debug information" })

vim.api.nvim_create_user_command('UniPackageClearCache', function()
    M.clear_cache()
end, { desc = "Clear all UniPackage caches" })

return M

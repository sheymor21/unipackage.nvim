local utils = require("unipackage.core.utils")
local actions = require("unipackage.core.actions")
local ui = require("unipackage.core.ui")
local config = require("unipackage.core.config")

local M = {}

-- Setup function for user configuration
M.setup = function(user_config)
    return config.setup(user_config)
end

-- Legacy functions for backward compatibility
function M.list_packages()
    actions.list_packages()
end

function M.install_packages()
    ui.install_packages_dialog()
end

function M.uninstall_packages()
    ui.uninstall_packages_dialog()
end

-- New unified menu function
function M.package_menu()
    ui.package_menu()
end

-- Get configuration (for external access)
function M.get_config(key)
    return config.get(key)
end

-- Get preferred manager (for external access)
function M.get_preferred_manager()
    return utils.get_preferred_manager()
end

-- Get detected managers (for external access)
function M.get_detected_managers()
    return utils.get_detected_managers()
end

-- Debug function to show detection info
function M.debug()
    local detected = utils.get_detected_managers()
    local preferred = utils.get_preferred_manager()
    local patterns = config.get_detection_patterns()
    local language = config.get_detected_language()
    local cwd = vim.fn.getcwd()

    local msg = "UniPackage Debug Info:\n\n"
    msg = msg .. "Current directory: " .. cwd .. "\n"
    msg = msg .. "Detected language: " .. (language or "none") .. "\n\n"
    msg = msg .. "Detected managers: " .. vim.inspect(detected) .. "\n\n"
    msg = msg .. "Preferred manager: " .. (preferred or "nil") .. "\n\n"
    msg = msg .. "Checking lock files:\n"

    for manager, files in pairs(patterns) do
        msg = msg .. "  " .. manager .. ":\n"
        for _, file in ipairs(files) do
            local exists = vim.fn.filereadable(cwd .. "/" .. file) == 1
            msg = msg .. "    " .. file .. ": " .. (exists and "✓ FOUND" or "✗ not found") .. "\n"
        end
    end

    vim.notify(msg, vim.log.levels.INFO)
end

-- Create user commands
vim.api.nvim_create_user_command('UniPackageList', function()
    M.list_packages()
end, { desc = "List packages for detected package managers" })

vim.api.nvim_create_user_command('UniPackageInstall', function()
    M.install_packages()
end, { desc = "Interactive package installation" })

vim.api.nvim_create_user_command('UniPackageUninstall', function()
    M.uninstall_packages()
end, { desc = "Interactive package uninstallation" })

vim.api.nvim_create_user_command('UniPackageMenu', function()
    M.package_menu()
end, { desc = "Unified package management menu with install, list, and uninstall options" })

vim.api.nvim_create_user_command('UniPackageSetup', function(opts)
    local user_config = {}

    if opts.args and opts.args ~= "" then
        -- Try to parse as JSON if arguments provided
        local ok, parsed = pcall(vim.fn.json_decode, opts.args)
        if ok then
            user_config = parsed
        else
            vim.notify("Invalid JSON configuration for UniPackageSetup", vim.log.levels.ERROR)
            return
        end
    end

    M.setup(user_config)
end, {
    desc = "Configure UniPackage settings",
    nargs = "*",
    complete = function()
        return {
            '{"package_managers": ["bun", "npm"]}',
            '{"package_managers": ["npm", "bun"]}',
            '{"fallback_to_any": false}',
            '{"warn_on_fallback": true}'
        }
    end
})

vim.api.nvim_create_user_command('UniPackageDebug', function()
    M.debug()
end, { desc = "Show UniPackage detection debug information" })

return M

local M = {}

local modules = require("unipackage.core.modules")
local error_handler = require("unipackage.core.error")

--- Get manager module with error handling
-- @param manager string: Package manager name
-- @return table|nil: Manager module or nil on error
local function get_manager_module(manager)
    local module = modules.load(manager)
    if not module then
        error_handler.handle("actions", string.format("Package manager '%s' not available", manager))
    end
    return module
end

--- Get manager or show error
-- @param manager string|nil: Manager name or nil to detect
-- @return string|nil: Manager name or nil
local function get_manager(manager)
    if manager then
        return manager
    end

    local config = require("unipackage.core.config")
    manager = config.get_preferred_manager()

    if not manager then
        error_handler.handle("actions",
            "No package manager available. Check your project files or enable fallback mode.",
            vim.log.levels.WARN)
    end

    return manager
end

--- Installs packages using the detected package manager
-- @param packages table: list of packages to install
-- @param manager string|nil: specific manager to use (auto-detects if nil)
function M.install_packages(packages, manager)
    manager = get_manager(manager)
    if not manager then
        return
    end

    local manager_module = get_manager_module(manager)
    if not manager_module then
        return
    end

    local args = {"install"}
    vim.list_extend(args, packages)
    manager_module.run_command(args)
end

--- Uninstalls packages using the detected package manager
-- @param packages table: list of packages to uninstall
-- @param manager string|nil: specific manager to use (auto-detects if nil)
function M.uninstall_packages(packages, manager)
    manager = get_manager(manager)
    if not manager then
        return
    end

    -- Go doesn't have traditional uninstall - use Mod Tidy instead
    if manager == "go" then
        error_handler.handle("actions",
            "Go doesn't support package uninstallation. Use 'Mod Tidy' instead.",
            vim.log.levels.WARN)
        return
    end

    local manager_module = get_manager_module(manager)
    if not manager_module then
        return
    end

    -- JavaScript managers
    local args = {"remove"}
    if manager == "npm" then
        args = {"uninstall"}  -- npm uses "uninstall", bun uses "remove"
    end
    vim.list_extend(args, packages)
    manager_module.run_command(args)
end

--- Lists packages using the detected package manager
-- @param manager string|nil: specific manager to use (auto-detects if nil)
function M.list_packages(manager)
    manager = get_manager(manager)
    if not manager then
        return
    end

    local manager_module = get_manager_module(manager)
    if not manager_module then
        return
    end

    manager_module.run_command({"list"})
end

--- Gets installed packages from the detected package manager
-- @param manager string|nil: specific manager to use (auto-detects if nil)
-- @return table: list of installed package names
function M.get_installed_packages(manager)
    manager = get_manager(manager)
    if not manager then
        return {}
    end

    local manager_module = get_manager_module(manager)
    if not manager_module then
        return {}
    end

    if manager_module.get_installed_packages then
        return manager_module.get_installed_packages()
    end

    return {}
end

--- Run go mod tidy for Go projects
function M.run_go_mod_tidy()
    local manager_module = get_manager_module("go")
    if not manager_module then
        return
    end

    manager_module.run_command({"tidy"})
end

--- Run dotnet restore for dotnet projects
function M.run_dotnet_restore()
    local manager_module = get_manager_module("dotnet")
    if not manager_module then
        return
    end

    manager_module.run_command({"restore"})
end

--- Add project reference for dotnet projects
-- @param project string: Project path to add as reference
function M.add_dotnet_reference(project)
    local manager_module = get_manager_module("dotnet")
    if not manager_module then
        return
    end

    manager_module.run_command({"reference", project})
end

return M

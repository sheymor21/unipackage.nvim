local M = {}
local utils = require("unipackage.core.utils")

-- Dynamic module loading for package managers
local function get_manager_module(manager)
    local ok, module = pcall(require, "unipackage." .. manager)
    if not ok then
        vim.notify(string.format("Package manager '%s' not implemented", manager), vim.log.levels.ERROR)
        return nil
    end
    return module
end

--- Installs packages using the detected package manager
-- @param packages table: list of packages to install
-- @param manager string|nil: specific manager to use (auto-detects if nil)
function M.install_packages(packages, manager)
    manager = manager or utils.get_manager_for_project()
    if not manager then
        vim.notify("No package manager available", vim.log.levels.ERROR)
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
    manager = manager or utils.get_manager_for_project()
    if not manager then
        vim.notify("No package manager available", vim.log.levels.ERROR)
        return
    end
    
    local manager_module = get_manager_module(manager)
    if not manager_module then
        return
    end
    
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
    manager = manager or utils.get_manager_for_project()
    if not manager then
        vim.notify("No package manager available", vim.log.levels.ERROR)
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
    manager = manager or utils.get_manager_for_project()
    if not manager then
        return {}
    end
    
    local manager_module = get_manager_module(manager)
    if not manager_module then
        return {}
    end
    
    if manager_module.get_installed_packages then
        return manager_module.get_installed_packages()
    else
        -- Fallback: try to parse list command output
        return {}
    end
end

return M
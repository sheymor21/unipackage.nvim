local M = {}
local utils = require("unipackage.core.utils")

-- Module cache for loaded manager modules
local manager_module_cache = {}

-- Dynamic module loading for package managers with caching
local function get_manager_module(manager)
    -- Check cache first
    if manager_module_cache[manager] then
        return manager_module_cache[manager]
    end

    local module = nil
    local error_msg = nil

    -- Check if it's a Go module
    if manager == "go" then
        local ok, loaded_module = pcall(require, "unipackage.languages.go.go")
        if ok then
            module = loaded_module
        else
            error_msg = "Go package manager not available"
        end
    -- Check if it's a dotnet module
    elseif manager == "dotnet" then
        local ok, loaded_module = pcall(require, "unipackage.languages.dotnet.dotnet")
        if ok then
            module = loaded_module
        else
            error_msg = "Dotnet package manager not available"
        end
    -- JavaScript managers
    else
        local ok, loaded_module = pcall(require, "unipackage.languages.javascript." .. manager)
        if ok then
            module = loaded_module
        else
            error_msg = string.format("Package manager '%s' not implemented", manager)
        end
    end

    -- Cache the result (even nil to avoid repeated require calls)
    manager_module_cache[manager] = module

    if not module then
        vim.notify(error_msg, vim.log.levels.ERROR)
    end

    return module
end

--- Clear module cache (useful for testing/reloading)
function M.clear_module_cache()
    manager_module_cache = {}
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

    -- Go doesn't have traditional uninstall - use Mod Tidy instead
    if manager == "go" then
        vim.notify("Go doesn't support package uninstallation. Use 'Mod Tidy' instead.", vim.log.levels.WARN)
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

--- Run go mod tidy for Go projects
function M.run_go_mod_tidy()
    local manager_module = get_manager_module("go")
    if not manager_module then
        vim.notify("Go package manager not available", vim.log.levels.ERROR)
        return
    end
    
    manager_module.run_command({"tidy"})
end

--- Run dotnet restore for dotnet projects
function M.run_dotnet_restore()
    local manager_module = get_manager_module("dotnet")
    if not manager_module then
        vim.notify("Dotnet package manager not available", vim.log.levels.ERROR)
        return
    end
    
    manager_module.run_command({"restore"})
end

--- Add project reference for dotnet projects
function M.add_dotnet_reference(project)
    local manager_module = get_manager_module("dotnet")
    if not manager_module then
        vim.notify("Dotnet package manager not available", vim.log.levels.ERROR)
        return
    end
    
    manager_module.run_command({"reference", project})
end

return M
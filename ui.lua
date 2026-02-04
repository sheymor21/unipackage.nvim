local M = {}

-- Module dependencies
local utils = require("unipackage.utils")
local actions = require("unipackage.actions")

-- Safe wrapper functions to handle closure scoping issues
local function safe_install_packages(packages)
    local actions = require("unipackage.actions")
    return actions.install_packages(packages)
end

local function safe_uninstall_packages(packages)
    local actions = require("unipackage.actions")
    return actions.uninstall_packages(packages)
end

local function safe_list_packages()
    local actions = require("unipackage.actions")
    return actions.list_packages()
end

local function safe_get_installed_packages()
    local actions = require("unipackage.actions")
    return actions.get_installed_packages()
end

--- Shows interactive package installation dialog
function M.install_packages_dialog()
    local preferred_manager = utils.get_preferred_manager()
    
    if not preferred_manager then
        vim.notify("No supported package manager detected (bun or npm required)", vim.log.levels.ERROR)
        return
    end
    
    vim.ui.input({
        prompt = string.format("📦 Enter package(s) to install (%s):", preferred_manager:upper()),
        default = "",
        completion = "file",
        relative = "editor",
        prefer_width = 80,
        max_width = { 160, 0.9 },
        title_pos = "center",
        border = "rounded",
    }, function(input)
        if not input or input == "" then
            vim.notify("Package installation cancelled", vim.log.levels.WARN)
            return
        end
        
        -- Parse packages (handle multiple spaces)
        local packages = {}
        for pkg in input:gmatch("[^%s]+") do
            table.insert(packages, pkg)
        end
        
        if #packages == 0 then
            vim.notify("No valid package names provided", vim.log.levels.WARN)
            return
        end
        
        -- Multi-package confirmation
        if #packages > 1 then
            vim.ui.select({"Yes", "No"}, {
                prompt = string.format("Install these %d packages with %s?\n  • %s", #packages, preferred_manager:upper(), table.concat(packages, "\n  • ")),
            }, function(choice)
                if choice == "Yes" then
                    safe_install_packages(packages)
                end
            end)
        else
            safe_install_packages(packages)
        end
    end)
end

--- Shows interactive package uninstallation dialog
function M.uninstall_packages_dialog()
    local preferred_manager = utils.get_preferred_manager()
    
    if not preferred_manager then
        vim.notify("No supported package manager detected (bun or npm required)", vim.log.levels.ERROR)
        return
    end
    
    local packages = safe_get_installed_packages()
    
    if #packages == 0 then
        vim.notify("No packages found to uninstall", vim.log.levels.WARN)
        return
    end
    
    vim.ui.select(packages, {
        prompt = string.format("🗑️ Select package(s) to uninstall (%s):", preferred_manager:upper()),
        format_item = function(item)
            return "• " .. item
        end,
    }, function(selected)
        if not selected then
            vim.notify("Package uninstallation cancelled", vim.log.levels.WARN)
            return
        end
        
        vim.ui.select({"Yes", "No"}, {
            prompt = string.format("Uninstall package: %s?", selected),
        }, function(choice)
            if choice == "Yes" then
                safe_uninstall_packages({selected})
            end
        end)
    end)
end

--- Shows unified package management menu with lock file priority
function M.package_menu()
    local detected = utils.get_detected_managers()
    local preferred_manager = utils.get_preferred_manager()
    local project_info = ""
    
    if preferred_manager then
        if #detected > 0 then
            project_info = string.format("🔍 Detected: %s\n📌 Using: %s (Lock file priority)\n\n", 
                table.concat(detected, ", "), preferred_manager:upper())
        else
            project_info = string.format("📌 Using: %s (Fallback)\n\n", preferred_manager:upper())
        end
    else
        project_info = "❌ No supported package manager found\n\n"
    end
    
    local options = {
        { name = string.format("➕ Install packages (%s)", preferred_manager and preferred_manager:upper() or "None"), 
          func = M.install_packages_dialog },
        { name = string.format("📄 List packages (%s)", preferred_manager and preferred_manager:upper() or "None"), 
          func = safe_list_packages },
        { name = string.format("➖ Uninstall packages (%s)", preferred_manager and preferred_manager:upper() or "None"), 
          func = M.uninstall_packages_dialog }
    }
    
    local option_names = {}
    for _, opt in ipairs(options) do
        table.insert(option_names, opt.name)
    end
    
    vim.ui.select(option_names, {
        prompt = project_info .. "📦 Package Management:",
        format_item = function(item)
            return item
        end,
    }, function(choice)
        if not choice then
            vim.notify("Package management cancelled", vim.log.levels.WARN)
            return
        end
        
        for _, opt in ipairs(options) do
            if opt.name == choice then
                opt.func()
                break
            end
        end
    end)
end

return M
local M = {}

local config = require("unipackage.core.config")
local utils = require("unipackage.core.utils")
local actions = require("unipackage.core.actions")

local function load_manager_module(manager)
    -- Check if it's a Go module
    if manager == "go" then
        local ok, module = pcall(require, "unipackage.languages.go.go")
        return ok and module or nil
    end

    -- Check if it's a dotnet module
    if manager == "dotnet" then
        local ok, module = pcall(require, "unipackage.languages.dotnet.dotnet")
        return ok and module or nil
    end

    -- JavaScript managers
    local module_path = "unipackage.languages.javascript." .. manager
    local ok, module = pcall(require, module_path)
    return ok and module or nil
end

-- Package installation dialog
function M.install_packages_dialog(manager)
    manager = manager or utils.get_manager_for_project()
    local module = load_manager_module(manager)

    if not module then
        vim.notify("Package manager " .. manager .. " not available", vim.log.levels.ERROR)
        return
    end

    local detected_managers = utils.get_detected_managers()
    local project_info = "🔍 Detected: " ..
    table.concat(detected_managers, ", ") .. "\n📌 Using: " .. manager:upper() .. "\n\n"

    vim.ui.input({
        prompt = "📦 Install package(s) (" .. manager:upper() .. "):",
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

        local packages = {}
        for pkg in input:gmatch("[^%s]+") do
            table.insert(packages, pkg)
        end

        if #packages == 0 then
            vim.notify("No valid package names provided", vim.log.levels.WARN)
            return
        end

        if #packages > 1 then
            vim.ui.select({ "Yes", "No" }, {
                prompt = "Install these " ..
                #packages .. " packages with " .. manager:upper() .. "?\n  • " .. table.concat(packages, "\n  • "),
            }, function(choice)
                if choice == "Yes" then
                    actions.install_packages(packages, manager)
                end
            end)
        else
            actions.install_packages(packages, manager)
        end
    end)
end

-- Package uninstallation dialog
function M.uninstall_packages_dialog(manager)
    manager = manager or utils.get_manager_for_project()
    local module = load_manager_module(manager)

    if not module then
        vim.notify("Package manager " .. manager .. " not available", vim.log.levels.ERROR)
        return
    end

    local packages = actions.get_installed_packages(manager)

    if #packages == 0 then
        vim.notify("No packages found to uninstall", vim.log.levels.WARN)
        return
    end

    vim.ui.select(packages, {
        prompt = "🗑️ Select package(s) to uninstall (" .. manager:upper() .. "):",
        format_item = function(item)
            return "• " .. item
        end,
    }, function(selected)
        if not selected then
            vim.notify("Package uninstallation cancelled", vim.log.levels.WARN)
            return
        end

        vim.ui.select({ "Yes", "No" }, {
            prompt = "Uninstall package: " .. selected .. "?",
        }, function(choice)
            if choice == "Yes" then
                actions.uninstall_packages({ selected }, manager)
            end
        end)
    end)
end

-- Unified package management menu
function M.package_menu(manager)
    manager = manager or utils.get_manager_for_project()
    local module = load_manager_module(manager)

    if not module then
        vim.notify("Package manager " .. manager .. " not available", vim.log.levels.ERROR)
        return
    end

    local detected_managers = utils.get_detected_managers()

    local project_info = "🔍 Detected: " ..
    table.concat(detected_managers, ", ") .. "\n📌 Using: " .. manager:upper() .. "\n\n"

    local options
    if manager == "go" then
        -- Go-specific menu
        options = {
            {
                name = "➕ Install packages (" .. manager:upper() .. ")",
                func = function() M.install_packages_dialog(manager) end
            },
            {
                name = "📄 List packages (" .. manager:upper() .. ")",
                func = function() actions.list_packages(manager) end
            },
            {
                name = "🧹 Mod Tidy (" .. manager:upper() .. ")",
                func = function()
                    vim.ui.select({ "Yes", "No" }, {
                        prompt = "Run 'go mod tidy' to clean up dependencies?",
                    }, function(choice)
                        if choice == "Yes" then
                            actions.run_go_mod_tidy()
                        end
                    end)
                end
            }
        }
    elseif manager == "dotnet" then
        -- Dotnet-specific menu
        options = {
            {
                name = "➕ Install packages (" .. manager:upper() .. ")",
                func = function() M.install_packages_dialog(manager) end
            },
            {
                name = "📄 List packages (" .. manager:upper() .. ")",
                func = function() actions.list_packages(manager) end
            },
            {
                name = "➖ Uninstall packages (" .. manager:upper() .. ")",
                func = function() M.uninstall_packages_dialog(manager) end
            },
            {
                name = "🔄 Restore packages (" .. manager:upper() .. ")",
                func = function()
                    vim.ui.select({ "Yes", "No" }, {
                        prompt = "Run 'dotnet restore' to restore packages?",
                    }, function(choice)
                        if choice == "Yes" then
                            actions.run_dotnet_restore()
                        end
                    end)
                end
            },
            {
                name = "🔗 Add project reference (" .. manager:upper() .. ")",
                func = function() M.add_reference_dialog(manager) end
            }
        }
    else
        -- Standard menu for other managers
        options = {
            {
                name = "➕ Install packages (" .. manager:upper() .. ")",
                func = function() M.install_packages_dialog(manager) end
            },
            {
                name = "📄 List packages (" .. manager:upper() .. ")",
                func = function() actions.list_packages(manager) end
            },
            {
                name = "➖ Uninstall packages (" .. manager:upper() .. ")",
                func = function() M.uninstall_packages_dialog(manager) end
            }
        }
    end

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

-- Add project reference dialog for dotnet
function M.add_reference_dialog(manager)
    manager = manager or utils.get_manager_for_project()
    local module = load_manager_module(manager)

    if not module then
        vim.notify("Package manager " .. manager .. " not available", vim.log.levels.ERROR)
        return
    end

    -- Get list of available projects
    local projects = module.get_projects()

    if #projects == 0 then
        vim.notify("No projects found in solution", vim.log.levels.WARN)
        return
    end

    vim.ui.select(projects, {
        prompt = "🔗 Select project to add as reference:",
        format_item = function(item)
            return "• " .. item
        end,
    }, function(selected)
        if not selected then
            vim.notify("Add reference cancelled", vim.log.levels.WARN)
            return
        end

        vim.ui.select({ "Yes", "No" }, {
            prompt = "Add reference to: " .. selected .. "?",
        }, function(choice)
            if choice == "Yes" then
                actions.add_dotnet_reference(selected)
            end
        end)
    end)
end

return M

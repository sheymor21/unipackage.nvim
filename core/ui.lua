local M = {}

local function load_manager_module(manager, lang)
    local module_path = string.format("unipackage.%s.%s", lang, manager)
    local ok, module = pcall(require, module_path)
    return ok and module or nil
end

local function load_core_modules()
    local config = require("unipackage.core.config")
    local utils = require("unipackage.core.utils")
    local actions = require("unipackage.core.actions")

    return {
        config = config,
        utils = utils,
        actions = actions
    }
end

-- Package installation dialog
function M.install_packages_dialog(manager, lang)
    manager = manager or M.get_manager_for_project()
    lang = lang or M.detect_project_language()
    local module = load_manager_module(manager, lang)

    if not module then
        vim.notify("Package manager " .. manager .. " not available for language " .. lang, vim.log.levels.ERROR)
        return
    end

    local detected_managers = module.get_available_managers()
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
                    M.install_packages(packages, manager, lang)
                end
            end)
        else
            M.install_packages(packages, manager, lang)
        end
    end)
end

-- Package uninstallation dialog
function M.uninstall_packages_dialog(manager, lang)
    manager = manager or M.get_manager_for_project()
    lang = lang or M.detect_project_language()
    local module = load_manager_module(manager, lang)

    if not module then
        vim.notify("Package manager " .. manager .. " not available for language " .. lang, vim.log.levels.ERROR)
        return
    end

    local packages = module.get_installed_packages()

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
                M.uninstall_packages({ selected }, manager, lang)
            end
        end)
    end)
end

-- Unified package management menu
function M.package_menu(manager, lang)
    manager = manager or M.get_manager_for_project()
    lang = lang or M.detect_project_language()
    local module = load_manager_module(manager, lang)

    if not module then
        vim.notify("Package manager " .. manager .. " not available for language " .. lang, vim.log.levels.ERROR)
        return
    end

    local detected_managers = module.get_available_managers()

    local project_info = "🔍 Detected: " ..
    table.concat(detected_managers, ", ") .. "\n📌 Using: " .. manager:upper() .. "\n\n"

    local options = {
        {
            name = "➕ Install packages (" .. manager:upper() .. ")",
            func = function() M.install_packages_dialog(manager, lang) end
        },
        {
            name = "📄 List packages (" .. manager:upper() .. ")",
            func = function() M.list_packages(manager, lang) end
        },
        {
            name = "➖ Uninstall packages (" .. manager:upper() .. ")",
            func = function() M.uninstall_packages_dialog(manager, lang) end
        }
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

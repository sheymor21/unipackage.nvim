local M = {}

local config = require("unipackage.core.config")
local utils = require("unipackage.core.utils")
local actions = require("unipackage.core.actions")

-- Module cache for loaded manager modules (shared with actions.lua)
local manager_module_cache = {}

local function load_manager_module(manager)
    -- Check cache first
    if manager_module_cache[manager] then
        return manager_module_cache[manager]
    end

    local module = nil

    -- Check if it's a Go module
    if manager == "go" then
        local ok, loaded_module = pcall(require, "unipackage.languages.go.go")
        if ok then
            module = loaded_module
        end
    -- Check if it's a dotnet module
    elseif manager == "dotnet" then
        local ok, loaded_module = pcall(require, "unipackage.languages.dotnet.dotnet")
        if ok then
            module = loaded_module
        end
    -- JavaScript managers
    else
        local module_path = "unipackage.languages.javascript." .. manager
        local ok, loaded_module = pcall(require, module_path)
        if ok then
            module = loaded_module
        end
    end

    -- Cache the result
    manager_module_cache[manager] = module
    return module
end

-- Select project for dotnet operations (async callback-based)
function M.select_dotnet_project(module, operation, callback)
    local projects = module.get_projects()

    if #projects == 0 then
        vim.notify("No .csproj files found in solution", vim.log.levels.ERROR)
        callback(nil)
        return
    end

    if #projects == 1 then
        callback(projects[1])
        return
    end

    -- Multiple projects - show selection dialog
    local nuget_search = require("unipackage.utils.nuget_search")
    local options = {}

    for _, project in ipairs(projects) do
        local framework = nuget_search.get_project_framework(project)
        local display = project
        if framework then
            local fw_display = nuget_search.get_framework_display(framework)
            display = string.format("%s (%s)", project, fw_display)
        end
        table.insert(options, display)
    end

    vim.ui.select(options, {
        prompt = "📁 Select project for " .. operation .. ":",
    }, function(choice, idx)
        if not idx then
            callback(nil)
        else
            callback(projects[idx])
        end
    end)
end

-- Search NuGet and install for dotnet (async)
function M.search_and_install_dotnet(query, project, manager)
    local nuget_search = require("unipackage.utils.nuget_search")
    local framework = nuget_search.get_project_framework(project)

    -- Show loading notification
    local loading_notif = vim.notify("🔍 Searching NuGet for: " .. query .. " (framework: " .. (framework or "any") .. ")", vim.log.levels.INFO, {
        title = "Package Search",
        timeout = false,
    })

    -- Async search
    nuget_search.search_packages_async(query, framework, 20, function(results, error)
        -- Clear loading notification
        vim.notify("", vim.log.levels.INFO, { replace = loading_notif, timeout = 1 })

        if error then
            vim.notify("❌ Search failed: " .. error, vim.log.levels.ERROR)
            return
        end

        if #results == 0 then
            vim.notify("❌ No packages found for: " .. query, vim.log.levels.WARN)
            return
        end

        -- Format for display
        local options = {}
        for _, pkg in ipairs(results) do
            local formatted = nuget_search.format_search_result(pkg)
            table.insert(options, formatted)
        end

        -- Fuzzy select
        vim.ui.select(options, {
            prompt = "🔍 Search results for '" .. query .. "':",
        }, function(choice, idx)
            if not choice or not idx then
                vim.notify("Search cancelled", vim.log.levels.WARN)
                return
            end

            local selected_pkg = results[idx]

            -- Install (dotnet doesn't use @version syntax in the same way)
            vim.ui.select({"Yes", "No"}, {
                prompt = "📦 Install " .. selected_pkg.id .. " to " .. project .. "?",
            }, function(choice)
                if choice == "Yes" then
                    -- Use dotnet add package command with project
                    local Terminal = require("toggleterm.terminal").Terminal
                    local runner = Terminal:new({
                        direction = "float",
                        close_on_exit = false,
                        hidden = true,
                    })
                    runner.cmd = "dotnet add " .. project .. " package " .. selected_pkg.id
                    runner:toggle()
                    vim.notify("📦 Installing " .. selected_pkg.id .. " to " .. project, vim.log.levels.INFO)
                else
                    vim.notify("Installation cancelled", vim.log.levels.WARN)
                end
            end)
        end)
    end)
end

-- Package installation dialog
function M.install_packages_dialog(manager)
    manager = manager or utils.get_manager_for_project_silent()
    if not manager then
        vim.notify("UniPackage: No package manager available. Check your project files or enable fallback mode.", vim.log.levels.WARN)
        return
    end
    
    local module = load_manager_module(manager)
    if not module then
        vim.notify("Package manager " .. manager .. " not available", vim.log.levels.ERROR)
        return
    end

    local detected_managers = utils.get_detected_managers()
    local project_info = "🔍 Detected: " ..
    table.concat(detected_managers, ", ") .. "\n📌 Using: " .. manager:upper() .. "\n\n"

    -- For dotnet: select project first, then show input in callback
    if manager == "dotnet" then
        M.select_dotnet_project(module, "install", function(selected_project)
            if not selected_project then
                vim.notify("Project selection cancelled", vim.log.levels.WARN)
                return
            end

            -- Show input dialog after project selection
            vim.ui.input({
                prompt = "📦 Install package(s) (" .. manager:upper() .. ") [type to search]:",
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

                local nuget_search = require("unipackage.utils.nuget_search")
                if nuget_search.is_search_query(input) then
                    -- NuGet search mode
                    M.search_and_install_dotnet(input, selected_project, manager)
                else
                    -- Direct install mode for dotnet
                    -- Handle PackageId@version format
                    local package_id = input
                    local version = nil

                    if input:match("@") then
                        local parts = {}
                        for part in input:gmatch("[^@]+") do
                            table.insert(parts, part)
                        end
                        package_id = parts[1]
                        version = parts[2]

                        -- If version is empty or "latest", don't specify version
                        if version == "" or version == "latest" then
                            version = nil
                        end
                    end

                    -- Build dotnet add command
                    local cmd = "dotnet add " .. selected_project .. " package " .. package_id
                    if version then
                        cmd = cmd .. " --version " .. version
                    end

                    local Terminal = require("toggleterm.terminal").Terminal
                    local runner = Terminal:new({
                        direction = "float",
                        close_on_exit = false,
                        hidden = true,
                    })
                    runner.cmd = cmd
                    runner:toggle()
                    vim.notify("📦 Installing " .. package_id .. " to " .. selected_project, vim.log.levels.INFO)
                end
            end)
        end)
        return
    end

    -- For other managers (JS, Go), show input directly
    vim.ui.input({
        prompt = "📦 Install package(s) (" .. manager:upper() .. ") [type to search]:",
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

        -- Check if this is a JavaScript manager and if input should trigger search
        local is_js_manager = manager ~= "go" and manager ~= "dotnet"
        local npm_search = require("unipackage.utils.npm_search")

        if is_js_manager and npm_search.is_search_query(input) then
            -- Search mode
            M.search_and_install(input, manager)
        else
            -- Direct install mode
            local packages = {}
            for pkg in input:gmatch("[^%s]+") do
                table.insert(packages, pkg)
            end

            if #packages == 0 then
                vim.notify("No valid package names provided", vim.log.levels.WARN)
                return
            end

            -- Handle package@ (no version specified) -> use latest
            for i, pkg in ipairs(packages) do
                if pkg:match("@$") then
                    packages[i] = pkg .. "latest"
                    vim.notify("📦 No version specified, using @latest", vim.log.levels.INFO)
                end
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
        end
    end)
end

-- Search npm registry and install selected package (async)
-- Implements lazy loading: shows configurable batch size results initially, with "Load more..." option
function M.search_and_install(query, manager)
    local npm_search = require("unipackage.utils.npm_search")
    local cfg = require("unipackage.core.config")
    local INITIAL_LIMIT = cfg.get("search_batch_size") or 20
    local LOAD_MORE_LIMIT = INITIAL_LIMIT

    -- Show loading notification
    local loading_notif = vim.notify("🔍 Searching npm registry for: " .. query, vim.log.levels.INFO, {
        title = "Package Search",
        timeout = false,
    })

    -- Async search with larger limit to get more results in background
    npm_search.search_packages_async(query, manager, 250, function(all_results, error)
        -- Clear loading notification
        vim.notify("", vim.log.levels.INFO, { replace = loading_notif, timeout = 1 })

        if error then
            vim.notify("❌ Search failed: " .. error, vim.log.levels.ERROR)
            return
        end

        if #all_results == 0 then
            vim.notify("❌ No packages found for: " .. query, vim.log.levels.WARN)
            return
        end

        -- Function to show results with lazy loading
        local function show_results(start_idx, results)
            local end_idx = math.min(start_idx + INITIAL_LIMIT - 1, #results)
            local current_batch = {}

            for i = start_idx, end_idx do
                table.insert(current_batch, results[i])
            end

            -- Format for display
            local options = {}

            -- Add "Previous" option if not on first batch
            local has_previous = start_idx > 1
            if has_previous then
                table.insert(options, "⬅️  Previous batch")
            end

            for _, pkg in ipairs(current_batch) do
                local formatted = npm_search.format_search_result(pkg)
                table.insert(options, formatted)
            end

            -- Add "Load more..." option if there are more results
            local has_more = end_idx < #results
            if has_more then
                table.insert(options, "📥 Load more... (" .. tostring(#results - end_idx) .. " remaining)")
            end

            -- Fuzzy select
            vim.ui.select(options, {
                prompt = "🔍 Search results for '" .. query .. "' (" .. tostring(start_idx) .. "-" .. tostring(end_idx) .. " of " .. tostring(#results) .. "):",
            }, function(choice, idx)
                if not choice or not idx then
                    vim.notify("Search cancelled", vim.log.levels.WARN)
                    return
                end

                -- Check if "Previous" was selected
                if has_previous and idx == 1 then
                    -- Show previous batch
                    local prev_start = math.max(1, start_idx - INITIAL_LIMIT)
                    show_results(prev_start, results)
                    return
                end

                -- Check if "Load more..." was selected
                if has_more and idx == #options then
                    -- Show next batch
                    show_results(end_idx + 1, results)
                    return
                end

                -- Calculate actual index in current_batch (accounting for "Previous" option)
                local actual_idx = has_previous and (idx - 1) or idx
                local selected_pkg = current_batch[actual_idx]

                -- Install with @latest
                local full_pkg = selected_pkg.name .. "@latest"

                -- Confirm install
                vim.ui.select({"Yes", "No"}, {
                    prompt = "📦 Install " .. full_pkg .. "?",
                }, function(choice)
                    if choice == "Yes" then
                        actions.install_packages({full_pkg}, manager)
                    else
                        vim.notify("Installation cancelled", vim.log.levels.WARN)
                    end
                end)
            end)
        end

        -- Show first batch
        show_results(1, all_results)
    end)
end

-- Package uninstallation dialog
function M.uninstall_packages_dialog(manager)
    manager = manager or utils.get_manager_for_project_silent()
    if not manager then
        vim.notify("UniPackage: No package manager available. Check your project files or enable fallback mode.", vim.log.levels.WARN)
        return
    end
    
    local module = load_manager_module(manager)
    if not module then
        vim.notify("Package manager " .. manager .. " not available", vim.log.levels.ERROR)
        return
    end

    -- For dotnet: select project first using callback
    if manager == "dotnet" then
        M.select_dotnet_project(module, "uninstall", function(selected_project)
            if not selected_project then
                vim.notify("Project selection cancelled", vim.log.levels.WARN)
                return
            end

            -- Get packages from specific project
            local handle = io.popen("dotnet list " .. selected_project .. " package --format json 2>/dev/null")
            if not handle then
                vim.notify("Failed to get packages from " .. selected_project, vim.log.levels.ERROR)
                return
            end

            local output = handle:read("*a")
            handle:close()

            local packages = {}
            local ok, json_data = pcall(vim.fn.json_decode, output)
            if ok and json_data and json_data.projects then
                for _, project in ipairs(json_data.projects) do
                    if project.frameworks then
                        for _, framework in ipairs(project.frameworks) do
                            if framework.topLevelPackages then
                                for _, pkg in ipairs(framework.topLevelPackages) do
                                    if pkg.id then
                                        table.insert(packages, pkg.id)
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if #packages == 0 then
                vim.notify("No packages found in " .. selected_project, vim.log.levels.WARN)
                return
            end

            vim.ui.select(packages, {
                prompt = "🗑️ Select package to uninstall from " .. selected_project .. ":",
                format_item = function(item)
                    return "• " .. item
                end,
            }, function(selected)
                if not selected then
                    vim.notify("Package uninstallation cancelled", vim.log.levels.WARN)
                    return
                end

                vim.ui.select({ "Yes", "No" }, {
                    prompt = "Uninstall package: " .. selected .. " from " .. selected_project .. "?",
                }, function(choice)
                    if choice == "Yes" then
                        local Terminal = require("toggleterm.terminal").Terminal
                        local runner = Terminal:new({
                            direction = "float",
                            close_on_exit = false,
                            hidden = true,
                        })
                        runner.cmd = "dotnet remove " .. selected_project .. " package " .. selected
                        runner:toggle()
                        vim.notify("🗑️ Removing " .. selected .. " from " .. selected_project, vim.log.levels.INFO)
                    end
                end)
            end)
        end)
        return
    end

    -- Non-dotnet managers - use original behavior
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
    manager = manager or utils.get_manager_for_project_silent()
    if not manager then
        vim.notify("UniPackage: No package manager available. Check your project files or enable fallback mode.", vim.log.levels.WARN)
        return
    end
    
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
    manager = manager or utils.get_manager_for_project_silent()
    if not manager then
        vim.notify("UniPackage: No package manager available. Check your project files or enable fallback mode.", vim.log.levels.WARN)
        return
    end
    
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

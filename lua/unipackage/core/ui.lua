local M = {}

local config = require("unipackage.core.config")
local modules = require("unipackage.core.modules")
local actions = require("unipackage.core.actions")
local error_handler = require("unipackage.core.error")
local terminal = require("unipackage.core.terminal")
local version_ui = require("unipackage.core.version_ui")

-- =============================================================================
-- NOTIFICATION UTILITIES
-- =============================================================================

local notification_ids = {}
local notification_counter = 0

--- Show notification with consistent formatting
local function notify(message, level, opts)
    opts = opts or {}
    vim.notify(message, level, {
        replace = opts.replace,
        timeout = opts.timeout or 3000,
    })
end

--- Check if snacks notifier is active
local function is_snacks_notifier()
    local ok, snacks = pcall(require, "snacks.notifier")
    return ok and snacks ~= nil
end

--- Show loading notification
local function show_loading(message)
    notification_counter = notification_counter + 1
    local notif_id = notification_counter
    
    if is_snacks_notifier() then
        vim.notify(message, vim.log.levels.INFO, {
            title = "Package Search",
            timeout = 3000,
        })
        return nil
    else
        local handle = vim.notify(message, vim.log.levels.INFO, {
            title = "Package Search",
            timeout = false,
        })
        notification_ids[notif_id] = handle
        return notif_id
    end
end

--- Clear loading notification
local function clear_loading(notif_id)
    if not notif_id then
        return
    end
    
    local handle = notification_ids[notif_id]
    if not handle then
        return
    end
    
    vim.notify("✓ Search complete", vim.log.levels.INFO, { 
        replace = handle,
        timeout = 2000,
        title = "Package Search"
    })
    
    notification_ids[notif_id] = nil
end

-- =============================================================================
-- MANAGER UTILITIES
-- =============================================================================

local function get_manager_module(manager)
    local module = modules.load(manager)
    if not module then
        error_handler.handle("ui", "Package manager " .. manager .. " not available")
    end
    return module
end

local function get_manager(manager)
    if manager then
        return manager
    end
    manager = config.get_preferred_manager()
    if not manager then
        error_handler.handle("ui",
            "No package manager available. Check your project files or enable fallback mode.",
            vim.log.levels.WARN)
    end
    return manager
end

local function create_input_opts(prompt)
    return {
        prompt = prompt,
        default = "",
        completion = "file",
        relative = "editor",
        prefer_width = 80,
        max_width = { 160, 0.9 },
        title_pos = "center",
        border = "rounded",
    }
end

-- =============================================================================
-- DOTNET-SPECIFIC FUNCTIONS
-- =============================================================================

function M.select_dotnet_project(module, operation, callback)
    local projects = module.get_projects()

    if #projects == 0 then
        error_handler.handle("ui", "No .csproj files found in solution")
        callback(nil)
        return
    end

    if #projects == 1 then
        callback(projects[1])
        return
    end

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
        prompt = "[>] Select project for " .. operation .. ":",
    }, function(choice, idx)
        if not idx then
            callback(nil)
        else
            callback(projects[idx])
        end
    end)
end

local function handle_dotnet_direct_install(input, project)
    local package_id, version = input:match("^([^@]+)@?(.*)$")
    version = version ~= "" and version or nil

    if version == "latest" then
        version = nil
    end

    local cmd = "dotnet add " .. project .. " package " .. package_id
    if version then
        cmd = cmd .. " --version " .. version
    end

    terminal.run(cmd)
    notify("Installing " .. package_id .. " to " .. project, vim.log.levels.INFO)
end

function M.search_and_install_dotnet(query, project)
    local nuget_search = require("unipackage.utils.nuget_search")
    local framework = nuget_search.get_project_framework(project)

    local loading = show_loading("[~] Searching NuGet for: " .. query .. " (framework: " .. (framework or "any") .. ")")

    nuget_search.search_packages_async(query, framework, 20, function(results, err)
        clear_loading(loading)

        if err then
            error_handler.handle("ui", "Search failed: " .. err)
            return
        end

        if #results == 0 then
            notify("No packages found for: " .. query, vim.log.levels.WARN)
            return
        end

        local options = {}
        for _, pkg in ipairs(results) do
            table.insert(options, nuget_search.format_search_result(pkg))
        end

        vim.ui.select(options, {
            prompt = "[*] Search results for '" .. query .. "':",
        }, function(choice, idx)
            if not choice or not idx then
                notify("Search cancelled", vim.log.levels.WARN)
                return
            end

            local selected_pkg = results[idx]

            if config.is_version_selection_enabled("dotnet") then
                version_ui.select_nuget_version(selected_pkg.id, project, function(version)
                    if not version then
                        notify("Installation cancelled", vim.log.levels.WARN)
                        return
                    end

                    local cmd = "dotnet add " .. project .. " package " .. selected_pkg.id .. " --version " .. version
                    vim.ui.select({"[Y] Yes", "[N] No"}, {
                        prompt = "[+] Install " .. selected_pkg.id .. "@" .. version .. " to " .. project .. "?",
                    }, function(choice)
                        if choice == "[Y] Yes" then
                            terminal.run(cmd)
                            notify("Installing " .. selected_pkg.id .. "@" .. version .. " to " .. project, vim.log.levels.INFO)
                        else
                            notify("Installation cancelled", vim.log.levels.WARN)
                        end
                    end)
                end)
            else
                vim.ui.select({"[Y] Yes", "[N] No"}, {
                    prompt = "[+] Install " .. selected_pkg.id .. " to " .. project .. "?",
                }, function(choice)
                    if choice == "[Y] Yes" then
                        terminal.run("dotnet add " .. project .. " package " .. selected_pkg.id)
                        notify("Installing " .. selected_pkg.id .. " to " .. project, vim.log.levels.INFO)
                    else
                        notify("Installation cancelled", vim.log.levels.WARN)
                    end
                end)
            end
        end)
    end)
end

-- =============================================================================
-- SEARCH FUNCTIONS
-- =============================================================================

local function show_paginated_results(query, results, batch_size, manager)
    local function show_page(start_idx)
        local end_idx = math.min(start_idx + batch_size - 1, #results)
        local current_batch = {}

        for i = start_idx, end_idx do
            table.insert(current_batch, results[i])
        end

        local options = {}
        local has_previous = start_idx > 1
        local has_more = end_idx < #results

        if has_previous then
            table.insert(options, "[<] Previous batch")
        end

        local npm_search = require("unipackage.utils.npm_search")
        for _, pkg in ipairs(current_batch) do
            table.insert(options, npm_search.format_search_result(pkg))
        end

        if has_more then
            table.insert(options, "[+] Load more... (" .. tostring(#results - end_idx) .. " remaining)")
        end

        vim.ui.select(options, {
            prompt = string.format("[*] Search results for '%s' (%d-%d of %d):",
                query, start_idx, end_idx, #results),
        }, function(choice, idx)
            if not choice or not idx then
                notify("Search cancelled", vim.log.levels.WARN)
                return
            end

            if has_previous and idx == 1 then
                show_page(math.max(1, start_idx - batch_size))
                return
            end

            if has_more and idx == #options then
                show_page(end_idx + 1)
                return
            end

            local actual_idx = has_previous and (idx - 1) or idx
            local selected_pkg = current_batch[actual_idx]

            if config.is_version_selection_enabled("javascript") then
                version_ui.select_npm_version(selected_pkg.name, manager, function(version)
                    local full_pkg = selected_pkg.name .. "@" .. version
                    vim.ui.select({"[Y] Yes", "[N] No"}, {
                        prompt = "[+] Install " .. full_pkg .. "?",
                    }, function(choice)
                        if choice == "[Y] Yes" then
                            actions.install_packages({full_pkg}, manager)
                        else
                            notify("Installation cancelled", vim.log.levels.WARN)
                        end
                    end)
                end)
            else
                local full_pkg = selected_pkg.name .. "@latest"
                vim.ui.select({"[Y] Yes", "[N] No"}, {
                    prompt = "[+] Install " .. full_pkg .. "?",
                }, function(choice)
                    if choice == "[Y] Yes" then
                        actions.install_packages({full_pkg}, manager)
                    else
                        notify("Installation cancelled", vim.log.levels.WARN)
                    end
                end)
            end
        end)
    end

    show_page(1)
end

function M.search_and_install(query, manager)
    local npm_search = require("unipackage.utils.npm_search")
    local batch_size = config.get("search_batch_size") or 20

    local loading = show_loading("[~] Searching npm registry for: " .. query)

    npm_search.search_packages_async(query, manager, 250, function(all_results, err)
        clear_loading(loading)

        if err then
            error_handler.handle("ui", "Search failed: " .. err)
            return
        end

        if #all_results == 0 then
            notify("No packages found for: " .. query, vim.log.levels.WARN)
            return
        end

        show_paginated_results(query, all_results, batch_size, manager)
    end)
end

-- =============================================================================
-- INSTALLATION DIALOGS
-- =============================================================================

local function handle_direct_install(input, manager)
    local packages = {}
    for pkg in input:gmatch("[^%s]+") do
        table.insert(packages, pkg)
    end

    if #packages == 0 then
        notify("No valid package names provided", vim.log.levels.WARN)
        return
    end

    for i, pkg in ipairs(packages) do
        if pkg:match("@$") then
            packages[i] = pkg .. "latest"
            notify("[i] No version specified, using @latest", vim.log.levels.INFO)
        end
    end

    if #packages > 1 then
        vim.ui.select({"[Y] Yes", "[N] No"}, {
            prompt = string.format("[+] Install these %d packages with %s?\n  [*] %s",
                #packages, manager:upper(), table.concat(packages, "\n  [*] ")),
        }, function(choice)
            if choice == "[Y] Yes" then
                actions.install_packages(packages, manager)
            end
        end)
    else
        actions.install_packages(packages, manager)
    end
end

function M.install_packages_dialog(manager)
    manager = get_manager(manager)
    if not manager then
        return
    end

    local module = get_manager_module(manager)
    if not module then
        return
    end

    local detected = config.get_detected_managers()
    local project_info = "[i] Detected: " .. table.concat(detected, ", ") ..
                        " | [*] Using: " .. manager:upper() .. " | "

    if manager == "dotnet" then
        M.select_dotnet_project(module, "install", function(project)
            if not project then
                notify("Project selection cancelled", vim.log.levels.WARN)
                return
            end

            vim.ui.input(create_input_opts(project_info .. "[+] Install package(s) (" .. manager:upper() .. ") [type to search]:"),
                function(input)
                    if not input or input == "" then
                        notify("Package installation cancelled", vim.log.levels.WARN)
                        return
                    end

                    local nuget_search = require("unipackage.utils.nuget_search")
                    if nuget_search.is_search_query(input) then
                        M.search_and_install_dotnet(input, project, manager)
                    else
                        handle_dotnet_direct_install(input, project)
                    end
                end)
        end)
        return
    end

    vim.ui.input(create_input_opts(project_info .. "[+] Install package(s) (" .. manager:upper() .. ") [type to search]:"),
        function(input)
            if not input or input == "" then
                notify("Package installation cancelled", vim.log.levels.WARN)
                return
            end

            local is_js = manager ~= "go" and manager ~= "dotnet"
            local npm_search = require("unipackage.utils.npm_search")

            if is_js and npm_search.is_search_query(input) then
                M.search_and_install(input, manager)
            else
                handle_direct_install(input, manager)
            end
        end)
end

-- =============================================================================
-- UNINSTALLATION DIALOGS
-- =============================================================================

local function parse_dotnet_packages(output)
    local packages = {}
    local ok, json_data = pcall(vim.fn.json_decode, output)

    if not ok or not json_data or not json_data.projects then
        return packages
    end

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

    return packages
end

local function handle_dotnet_uninstall(project)
    local handle = io.popen("dotnet list " .. project .. " package --format json 2>/dev/null")
    if not handle then
        error_handler.handle("ui", "Failed to get packages from " .. project)
        return
    end

    local output = handle:read("*a")
    handle:close()

    local packages = parse_dotnet_packages(output)

    if #packages == 0 then
        notify("No packages found in " .. project, vim.log.levels.WARN)
        return
    end

    vim.ui.select(packages, {
        prompt = "[-] Select package to uninstall from " .. project .. ":",
        format_item = function(item)
            return "[*] " .. item
        end,
    }, function(selected)
        if not selected then
            notify("Package uninstallation cancelled", vim.log.levels.WARN)
            return
        end

        vim.ui.select({"[Y] Yes", "[N] No"}, {
            prompt = "[-] Uninstall package: " .. selected .. " from " .. project .. "?",
        }, function(choice)
            if choice == "[Y] Yes" then
                terminal.run("dotnet remove " .. project .. " package " .. selected)
                notify("Removing " .. selected .. " from " .. project, vim.log.levels.INFO)
            end
        end)
    end)
end

function M.uninstall_packages_dialog(manager)
    manager = get_manager(manager)
    if not manager then
        return
    end

    local module = get_manager_module(manager)
    if not module then
        return
    end

    if manager == "dotnet" then
        M.select_dotnet_project(module, "uninstall", function(project)
            if not project then
                notify("Project selection cancelled", vim.log.levels.WARN)
                return
            end
            handle_dotnet_uninstall(project)
        end)
        return
    end

    local packages = actions.get_installed_packages(manager)

    if #packages == 0 then
        notify("No packages found to uninstall", vim.log.levels.WARN)
        return
    end

    vim.ui.select(packages, {
        prompt = "[-] Select package(s) to uninstall (" .. manager:upper() .. "):",
        format_item = function(item)
            return "[*] " .. item
        end,
    }, function(selected)
        if not selected then
            notify("Package uninstallation cancelled", vim.log.levels.WARN)
            return
        end

        vim.ui.select({"[Y] Yes", "[N] No"}, {
            prompt = "[-] Uninstall package: " .. selected .. "?",
        }, function(choice)
            if choice == "[Y] Yes" then
                actions.uninstall_packages({selected}, manager)
            end
        end)
    end)
end

-- =============================================================================
-- MENU SYSTEM
-- =============================================================================

local function create_menu_options(manager)
    local base_options = {
        {
            name = "[+] Install packages (" .. manager:upper() .. ")",
            func = function() M.install_packages_dialog(manager) end
        },
        {
            name = "[#] List packages (" .. manager:upper() .. ")",
            func = function() actions.list_packages(manager) end
        },
    }

    if manager == "go" then
        table.insert(base_options, {
            name = "[~] Mod Tidy (" .. manager:upper() .. ")",
            func = function()
                vim.ui.select({"[Y] Yes", "[N] No"}, {
                    prompt = "Run 'go mod tidy' to clean up dependencies?",
                }, function(choice)
                    if choice == "[Y] Yes" then
                        actions.run_go_mod_tidy()
                    end
                end)
            end
        })
    elseif manager == "dotnet" then
        table.insert(base_options, {
            name = "[-] Uninstall packages (" .. manager:upper() .. ")",
            func = function() M.uninstall_packages_dialog(manager) end
        })
        table.insert(base_options, {
            name = "[*] Restore packages (" .. manager:upper() .. ")",
            func = function()
                vim.ui.select({"[Y] Yes", "[N] No"}, {
                    prompt = "Run 'dotnet restore' to restore packages?",
                }, function(choice)
                    if choice == "[Y] Yes" then
                        actions.run_dotnet_restore()
                    end
                end)
            end
        })
        table.insert(base_options, {
            name = "[>] Add project reference (" .. manager:upper() .. ")",
            func = function() M.add_reference_dialog(manager) end
        })
    else
        table.insert(base_options, {
            name = "[-] Uninstall packages (" .. manager:upper() .. ")",
            func = function() M.uninstall_packages_dialog(manager) end
        })
    end

    return base_options
end

function M.package_menu(manager)
    manager = get_manager(manager)
    if not manager then
        return
    end

    local detected = config.get_detected_managers()
    local project_info = "[i] Detected: " .. table.concat(detected, ", ") ..
                        " | [*] Using: " .. manager:upper() .. " | "

    local options = create_menu_options(manager)
    local option_names = {}
    for _, opt in ipairs(options) do
        table.insert(option_names, opt.name)
    end

    vim.ui.select(option_names, {
        prompt = project_info .. "[*] Package Management:",
    }, function(choice)
        if not choice then
            notify("Package management cancelled", vim.log.levels.WARN)
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

function M.add_reference_dialog(manager)
    manager = get_manager(manager)
    if not manager then
        return
    end

    local module = get_manager_module(manager)
    if not module then
        return
    end

    if manager ~= "dotnet" then
        notify("Project references are only supported for .NET projects", vim.log.levels.WARN)
        return
    end

    local projects = module.get_projects()

    if #projects == 0 then
        notify("No projects found in solution", vim.log.levels.WARN)
        return
    end

    vim.ui.select(projects, {
        prompt = "[>] Select project to add as reference:",
        format_item = function(item)
            return "[*] " .. item
        end,
    }, function(selected)
        if not selected then
            notify("Add reference cancelled", vim.log.levels.WARN)
            return
        end

        vim.ui.select({"[Y] Yes", "[N] No"}, {
            prompt = "Add reference to: " .. selected .. "?",
        }, function(choice)
            if choice == "[Y] Yes" then
                actions.add_dotnet_reference(selected)
            end
        end)
    end)
end

return M

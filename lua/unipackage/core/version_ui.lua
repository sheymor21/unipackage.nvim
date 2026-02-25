local M = {}

local config = require("unipackage.core.config")
local error_handler = require("unipackage.core.error")

-- =============================================================================
-- NOTIFICATION UTILITIES
-- =============================================================================

local notification_ids = {}
local notification_counter = 0

--- Show notification with consistent formatting
function M.notify(message, level, opts)
    opts = opts or {}
    vim.notify(message, level, {
        replace = opts.replace,
        timeout = opts.timeout or 3000,
    })
end

--- Check if snacks notifier is active
function M.is_snacks_notifier()
    local ok, snacks = pcall(require, "snacks.notifier")
    return ok and snacks ~= nil
end

--- Show loading notification
function M.show_loading(message)
    notification_counter = notification_counter + 1
    local notif_id = notification_counter
    
    if M.is_snacks_notifier() then
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
function M.clear_loading(notif_id)
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
-- VERSION SELECTION UTILITIES
-- =============================================================================

--- Sort major versions (descending)
local function sort_major_versions(groups)
    local major_list = {}
    for major, group in pairs(groups) do
        table.insert(major_list, {major = tonumber(major), group = group})
    end
    table.sort(major_list, function(a, b) return a.major > b.major end)
    return major_list
end

--- Show major version selection dialog
local function show_major_selection(package_name, major_list, on_select)
    local options = {}
    for _, item in ipairs(major_list) do
        table.insert(options, item.group.format_major(tostring(item.major), item.group))
    end

    vim.ui.select(options, {
        prompt = "[*] Select major version for " .. package_name .. ":",
    }, function(choice, idx)
        if not choice or not idx then
            M.notify("Version selection cancelled", vim.log.levels.WARN)
            on_select(nil)
            return
        end
        on_select(major_list[idx].major)
    end)
end

--- Show specific version selection dialog
local function show_version_selection(package_name, versions, on_select)
    local options = {}
    for _, version in ipairs(versions) do
        table.insert(options, version.format(version))
    end

    vim.ui.select(options, {
        prompt = "[*] Select version for " .. package_name .. ":",
    }, function(choice, idx)
        if not choice or not idx then
            M.notify("Version selection cancelled", vim.log.levels.WARN)
            on_select(nil)
            return
        end
        on_select(versions[idx])
    end)
end

--- Generic version selection flow
local function select_version_flow(package_name, version_api, on_complete)
    local version_config = config.get_version_selection_config()
    local include_prerelease = version_config.include_prerelease
    local max_versions = version_config.max_versions_shown

    M.notify("[~] Searching versions for: " .. package_name, vim.log.levels.INFO)
    local loading = M.show_loading("[~] Fetching versions for: " .. package_name)

    version_api.get_by_major(package_name, include_prerelease, function(groups, err)
        M.clear_loading(loading)

        if err then
            error_handler.handle("ui", "Failed to fetch versions: " .. err)
            on_complete(nil)
            return
        end

        if not groups or vim.tbl_isempty(groups) then
            M.notify("No versions found for: " .. package_name, vim.log.levels.WARN)
            on_complete(nil)
            return
        end

        local major_list = sort_major_versions(groups)
        
        show_major_selection(package_name, major_list, function(selected_major)
            if not selected_major then
                on_complete(nil)
                return
            end

            local version_loading = M.show_loading("[~] Loading versions for " .. selected_major .. ".x")

            version_api.get_for_major(package_name, selected_major, include_prerelease, max_versions, function(versions, verr)
                M.clear_loading(version_loading)

                if verr or not versions or #versions == 0 then
                    M.notify("No versions found for " .. selected_major .. ".x", vim.log.levels.WARN)
                    on_complete(nil)
                    return
                end

                show_version_selection(package_name, versions, function(selected_version)
                    on_complete(selected_version)
                end)
            end)
        end)
    end)
end

-- =============================================================================
-- NPM VERSION SELECTION
-- =============================================================================

function M.select_npm_version(package_name, manager, on_complete)
    local npm_versions = require("unipackage.utils.npm_versions")
    
    local version_api = {
        get_by_major = npm_versions.get_versions_by_major_async,
        get_for_major = npm_versions.get_versions_for_major_async,
        format_major = npm_versions.format_major_group,
        format = npm_versions.format_version,
    }

    select_version_flow(package_name, version_api, function(version)
        if not version then
            on_complete("latest")
        else
            on_complete(version)
        end
    end)
end

-- =============================================================================
-- NUGET VERSION SELECTION
-- =============================================================================

function M.select_nuget_version(package_id, project, on_complete)
    local nuget_versions = require("unipackage.utils.nuget_versions")
    
    local version_api = {
        get_by_major = nuget_versions.get_versions_by_major_async,
        get_for_major = nuget_versions.get_versions_for_major_async,
        format_major = nuget_versions.format_major_group,
        format = nuget_versions.format_version,
    }

    select_version_flow(package_id, version_api, function(version)
        on_complete(version)
    end)
end

return M

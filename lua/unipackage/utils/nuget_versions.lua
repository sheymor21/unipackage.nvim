local M = {}

local http = require("unipackage.utils.http")
local version_utils = require("unipackage.utils.version_utils")

-- =============================================================================
-- NUGET-SPECIFIC FETCHING
-- =============================================================================

local function get_cache_key(package_id)
    return "nuget_versions:" .. package_id
end

local function fetch_from_registry(package_id, callback)
    local cached = version_utils.get_cached(get_cache_key(package_id))
    if cached then
        callback(cached, nil)
        return
    end
    
    local url = string.format("https://api.nuget.org/v3-flatcontainer/%s/index.json", 
        package_id:lower())
    
    http.get(url, function(success, data, error)
        if not success then
            callback(nil, error or "Failed to fetch versions")
            return
        end
        
        if not data or not data.versions then
            callback(nil, "No versions found")
            return
        end
        
        local result = {
            versions = data.versions,
            fetched_at = os.time()
        }
        
        version_utils.set_cached(get_cache_key(package_id), result)
        callback(result, nil)
    end)
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

function M.get_versions_by_major_async(package_id, include_prerelease, callback)
    fetch_from_registry(package_id, function(data, error)
        if error then
            callback(nil, error)
            return
        end
        
        local filtered = version_utils.filter_prereleases(data.versions, include_prerelease)
        local groups = version_utils.group_by_major(filtered)
        callback(groups, nil)
    end)
end

function M.get_versions_for_major_async(package_id, major_version, include_prerelease, max_results, callback)
    fetch_from_registry(package_id, function(data, error)
        if error then
            callback(nil, error)
            return
        end
        
        local filtered = {}
        for _, version in ipairs(data.versions) do
            local parsed = version_utils.parse_semver(version)
            if parsed and parsed.major == major_version then
                if include_prerelease or not parsed.prerelease then
                    table.insert(filtered, version)
                end
            end
        end
        
        filtered = version_utils.sort_versions_descending(filtered)
        filtered = version_utils.limit_array(filtered, max_results)
        
        callback(filtered, nil)
    end)
end

-- =============================================================================
-- FORMATTING (Delegate to shared utilities)
-- =============================================================================

M.format_major_group = version_utils.format_major_group
M.format_version = version_utils.format_version

return M

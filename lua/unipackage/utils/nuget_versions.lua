local M = {}

local http = require("unipackage.utils.http")
local version_utils = require("unipackage.utils.version_utils")
local nuget_config = require("unipackage.utils.nuget_config")
local nuget_search = require("unipackage.utils.nuget_search")

-- =============================================================================
-- NUGET-SPECIFIC FETCHING
-- =============================================================================

local function get_cache_key(package_id, source_name)
    return "nuget_versions:" .. (source_name or "nuget.org") .. ":" .. package_id:lower()
end

-- Get the flatcontainer URL from service index
local function get_flatcontainer_url(service_index_data)
    if not service_index_data or not service_index_data.resources then
        return nil
    end
    
    for _, resource in ipairs(service_index_data.resources) do
        if resource["@type"] == "PackageBaseAddress/3.0.0" then
            return resource["@id"]
        end
    end
    
    return nil
end

-- Fetch versions from a specific source
local function fetch_from_source(package_id, source, callback)
    local cache_key = get_cache_key(package_id, source.name)
    local cached = version_utils.get_cached(cache_key)
    if cached then
        callback(cached, nil)
        return
    end
    
    -- Get service index to find PackageBaseAddress
    local service_index_url = nuget_config.get_service_index_url(source.url)
    local headers = nil
    if source.credentials then
        headers = nuget_config.get_auth_headers(source)
    end
    
    http.get(service_index_url, function(success, service_data, error)
        if not success then
            callback(nil, error or "Failed to get service index")
            return
        end
        
        local flatcontainer_url = get_flatcontainer_url(service_data)
        if not flatcontainer_url then
            -- Fallback to constructing URL for nuget.org style
            if source.url:match("nuget%.org") then
                flatcontainer_url = "https://api.nuget.org/v3-flatcontainer/"
            else
                callback(nil, "PackageBaseAddress not found in service index")
                return
            end
        end
        
        -- Ensure flatcontainer URL ends with /
        if not flatcontainer_url:match("/$") then
            flatcontainer_url = flatcontainer_url .. "/"
        end
        
        -- Build versions URL
        local versions_url = flatcontainer_url .. package_id:lower() .. "/index.json"
        
        http.get(versions_url, function(vsuccess, vdata, verror)
            if not vsuccess then
                -- Try without authentication for public feeds
                if source.credentials then
                    http.get(versions_url, function(vsuccess2, vdata2, verror2)
                        if not vsuccess2 then
                            callback(nil, verror2 or "Failed to fetch versions")
                            return
                        end
                        
                        if not vdata2 or not vdata2.versions then
                            callback(nil, "No versions found")
                            return
                        end
                        
                        local result = {
                            versions = vdata2.versions,
                            fetched_at = os.time(),
                            source = source.name
                        }
                        
                        version_utils.set_cached(cache_key, result)
                        callback(result, nil)
                    end, {headers = nil})
                else
                    callback(nil, verror or "Failed to fetch versions")
                end
                return
            end
            
            if not vdata or not vdata.versions then
                callback(nil, "No versions found")
                return
            end
            
            local result = {
                versions = vdata.versions,
                fetched_at = os.time(),
                source = source.name
            }
            
            version_utils.set_cached(cache_key, result)
            callback(result, nil)
        end, {headers = headers})
    end, {headers = headers})
end

-- Try fetching from all configured sources
local function fetch_from_registry(package_id, callback)
    local sources = nuget_search.get_package_sources()
    
    if not sources or #sources == 0 then
        callback(nil, "No package sources configured")
        return
    end
    
    local all_versions = {}
    local pending = #sources
    local has_error = false
    
    local function check_complete()
        pending = pending - 1
        if pending == 0 then
            if #all_versions > 0 then
                -- Merge and deduplicate versions from all sources
                local seen = {}
                local merged = {}
                for _, v in ipairs(all_versions) do
                    if not seen[v] then
                        seen[v] = true
                        table.insert(merged, v)
                    end
                end
                
                -- Sort versions
                table.sort(merged, function(a, b)
                    return version_utils.compare_versions(a, b) > 0
                end)
                
                local result = {
                    versions = merged,
                    fetched_at = os.time()
                }
                
                callback(result, nil)
            elseif has_error then
                callback(nil, "Failed to fetch versions from all sources")
            else
                callback(nil, "No versions found")
            end
        end
    end
    
    for _, source in ipairs(sources) do
        fetch_from_source(package_id, source, function(data, error)
            if data and data.versions then
                for _, v in ipairs(data.versions) do
                    table.insert(all_versions, v)
                end
            else
                has_error = true
            end
            check_complete()
        end)
    end
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
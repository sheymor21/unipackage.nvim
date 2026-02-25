local M = {}

local http = require("unipackage.utils.http")
local cache = require("unipackage.utils.cache")

local CACHE_DURATION = 30 * 60 -- 30 minutes in seconds

-- =============================================================================
-- SEMVER PARSING (Shared)
-- =============================================================================

--- Parse a semantic version string into components
-- @param version string: Version string (e.g., "18.2.0")
-- @return table: {major, minor, patch, prerelease} or nil if invalid
function M.parse_semver(version)
    local major, minor, patch, prerelease = version:match("^(%d+)%.(%d+)%.(%d+)-?([^%+]*)")
    
    if not major then
        return nil
    end
    
    return {
        major = tonumber(major),
        minor = tonumber(minor),
        patch = tonumber(patch),
        prerelease = prerelease and prerelease ~= "" and prerelease or nil,
        raw = version
    }
end

--- Check if version is a pre-release
function M.is_prerelease(version)
    local parsed = M.parse_semver(version)
    return parsed and parsed.prerelease ~= nil
end

--- Compare two semantic versions
-- @return number: -1 if v1 < v2, 0 if equal, 1 if v1 > v2
function M.compare_versions(v1, v2)
    if v1.major ~= v2.major then
        return v1.major > v2.major and 1 or -1
    end
    if v1.minor ~= v2.minor then
        return v1.minor > v2.minor and 1 or -1
    end
    if v1.patch ~= v2.patch then
        return v1.patch > v2.patch and 1 or -1
    end
    
    -- Pre-release versions have lower precedence
    if v1.prerelease and not v2.prerelease then
        return -1
    elseif not v1.prerelease and v2.prerelease then
        return 1
    elseif v1.prerelease and v2.prerelease then
        if v1.prerelease ~= v2.prerelease then
            return v1.prerelease > v2.prerelease and 1 or -1
        end
    end
    
    return 0
end

--- Group versions by major version
function M.group_by_major(versions)
    local groups = {}
    
    for _, version in ipairs(versions) do
        local parsed = M.parse_semver(version)
        if parsed then
            local major_key = tostring(parsed.major)
            if not groups[major_key] then
                groups[major_key] = {
                    major = parsed.major,
                    versions = {},
                    latest = nil
                }
            end
            table.insert(groups[major_key].versions, parsed)
        end
    end
    
    -- Sort versions within each group and find latest
    for _, group in pairs(groups) do
        table.sort(group.versions, function(a, b)
            return M.compare_versions(a, b) > 0
        end)
        group.latest = group.versions[1]
    end
    
    return groups
end

--- Sort versions descending
function M.sort_versions_descending(versions)
    table.sort(versions, function(a, b)
        local pa = M.parse_semver(a)
        local pb = M.parse_semver(b)
        if pa and pb then
            return M.compare_versions(pa, pb) > 0
        end
        return a > b
    end)
    return versions
end

--- Limit array size
function M.limit_array(arr, max_size)
    if not max_size or #arr <= max_size then
        return arr
    end
    local limited = {}
    for i = 1, max_size do
        table.insert(limited, arr[i])
    end
    return limited
end

--- Filter out pre-release versions
function M.filter_prereleases(versions, include_prerelease)
    if include_prerelease then
        return versions
    end
    
    local filtered = {}
    for _, version in ipairs(versions) do
        if not M.is_prerelease(version) then
            table.insert(filtered, version)
        end
    end
    return filtered
end

--- Format major version group for display
function M.format_major_group(major, group)
    local version_count = #group.versions
    local latest = group.latest
    
    return string.format("%d.x (Latest: %d.%d.%d, %d versions)",
        group.major,
        latest.major, latest.minor, latest.patch,
        version_count)
end

--- Format version for display
function M.format_version(version)
    local parsed = M.parse_semver(version)
    if not parsed then
        return version
    end
    
    if parsed.prerelease then
        return string.format("%d.%d.%d-%s", parsed.major, parsed.minor, parsed.patch, parsed.prerelease)
    end
    
    return string.format("%d.%d.%d", parsed.major, parsed.minor, parsed.patch)
end

-- =============================================================================
-- CACHE UTILITIES (Shared)
-- =============================================================================

function M.get_cached(key)
    local data, found = cache.get(key)
    return found and data or nil
end

function M.set_cached(key, data)
    cache.set(key, data, CACHE_DURATION)
end

return M

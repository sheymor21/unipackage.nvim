local M = {}

-- Import optimized utilities
local http = require("unipackage.utils.http")
local cache = require("unipackage.utils.cache")

local CACHE_DURATION = 30 * 60 -- 30 minutes in seconds

function M.get_search_service_url(callback)
    -- Check cache first
    local cached_url, found = cache.get("nuget:search_service_url")
    if found and cached_url then
        if callback then
            callback(cached_url)
        else
            return cached_url
        end
        return
    end

    local service_index_url = "https://api.nuget.org/v3/index.json"
    
    if callback then
        -- Async version
        http.get(service_index_url, function(success, data, error)
            if not success then
                vim.notify("Failed to get NuGet service URL: " .. (error or "Unknown error"), vim.log.levels.WARN)
                callback("https://api-v2v3search-0.nuget.org/query")
                return
            end

            local search_url = "https://api-v2v3search-0.nuget.org/query"
            if data and data.resources then
                for _, resource in ipairs(data.resources) do
                    if resource["@type"] and resource["@type"]:match("^SearchQueryService") then
                        search_url = resource["@id"]
                        break
                    end
                end
            end

            -- Cache for 24 hours (service URLs don't change often)
            cache.set("nuget:search_service_url", search_url, 24 * 60 * 60)
            callback(search_url)
        end)
    else
        -- Sync fallback
        local data, error = http.get_sync(service_index_url)
        if error then
            vim.notify("Failed to get NuGet service URL: " .. error, vim.log.levels.WARN)
            return "https://api-v2v3search-0.nuget.org/query"
        end

        local search_url = "https://api-v2v3search-0.nuget.org/query"
        if data and data.resources then
            for _, resource in ipairs(data.resources) do
                if resource["@type"] and resource["@type"]:match("^SearchQueryService") then
                    search_url = resource["@id"]
                    break
                end
            end
        end

        -- Cache for 24 hours
        cache.set("nuget:search_service_url", search_url, 24 * 60 * 60)
        return search_url
    end
end

function M.get_cached_search(query, framework)
    local key = string.format("nuget:%s-%s", query, framework or "any")
    local data, found = cache.get(key)
    return found and data or nil
end

function M.cache_search(query, framework, results)
    local key = string.format("nuget:%s-%s", query, framework or "any")
    cache.set(key, results, CACHE_DURATION)
end

function M.clear_expired_cache()
    cache.maintenance()
end

function M.parse_search_response(data)
    local results = {}

    if not data or not data.data then
        return results
    end

    for _, pkg in ipairs(data.data) do
        table.insert(results, {
            id = pkg.id,
            version = pkg.version,
            description = pkg.description or "",
            downloads = pkg.totalDownloads or 0,
            authors = pkg.authors or "",
            verified = pkg.verified or false
        })
    end

    return results
end

--- Search NuGet packages (async)
-- @param query string: search query
-- @param framework string|nil: target framework filter
-- @param limit number: maximum results (default 20)
-- @param callback function: callback(results, error)
function M.search_packages_async(query, framework, limit, callback)
    limit = limit or 20

    local cached = M.get_cached_search(query, framework)
    if cached then
        callback(cached, nil)
        return
    end

    M.get_search_service_url(function(search_url)
        local encoded_query = query:gsub(" ", "+")
        local url = string.format(
            "%s?q=%s&take=%d&prerelease=false",
            search_url,
            encoded_query,
            limit
        )

        if framework and framework ~= "" then
            url = url .. "&frameworks=" .. framework
        end

        http.get(url, function(success, data, error)
            if not success then
                vim.notify("NuGet search failed: " .. (error or "Unknown error"), vim.log.levels.ERROR)
                callback({}, error)
                return
            end

            local results = M.parse_search_response(data)

            if #results > 0 then
                M.cache_search(query, framework, results)
            end

            callback(results, nil)
        end)
    end)
end

--- Search NuGet packages (sync fallback)
-- @param query string: search query
-- @param framework string|nil: target framework filter
-- @param limit number: maximum results (default 20)
-- @return table: search results
function M.search_packages(query, framework, limit)
    limit = limit or 20

    local cached = M.get_cached_search(query, framework)
    if cached then
        return cached
    end

    local search_url = M.get_search_service_url()

    local encoded_query = query:gsub(" ", "+")
    local url = string.format(
        "%s?q=%s&take=%d&prerelease=false",
        search_url,
        encoded_query,
        limit
    )

    if framework and framework ~= "" then
        url = url .. "&frameworks=" .. framework
    end

    local data, error = http.get_sync(url)
    if error then
        vim.notify("NuGet search failed: " .. error, vim.log.levels.ERROR)
        return {}
    end

    local results = M.parse_search_response(data)

    if #results > 0 then
        M.cache_search(query, framework, results)
    end

    return results
end

function M.format_search_result(pkg)
    local id_version = string.format("%s @ %s", pkg.id, pkg.version)

    local downloads_str = ""
    if pkg.downloads and pkg.downloads > 0 then
        if pkg.downloads >= 1000000 then
            downloads_str = string.format(" (%.1fM dl)", pkg.downloads / 1000000)
        elseif pkg.downloads >= 1000 then
            downloads_str = string.format(" (%.1fK dl)", pkg.downloads / 1000)
        else
            downloads_str = string.format(" (%d dl)", pkg.downloads)
        end
    end

    local verified_str = ""
    if pkg.verified then
        verified_str = " ✓"
    end

    local desc = pkg.description or ""
    if #desc > 50 then
        desc = desc:sub(1, 47) .. "..."
    end

    return string.format("%s%s%s - %s", id_version, downloads_str, verified_str, desc)
end

function M.is_search_query(input)
    if not input or input:match("^%s*$") then
        return false
    end

    if input:match("@") then
        return false
    end

    if input:match(" ") then
        return false
    end

    return true
end

function M.get_project_framework(project_path)
    local file = io.open(project_path, "r")
    if not file then
        return nil
    end

    local content = file:read("*a")
    file:close()

    local framework = content:match("<TargetFramework>([^<]+)</TargetFramework>")

    if framework then
        return framework:gsub("%s+", "")
    end

    local frameworks = content:match("<TargetFrameworks>([^<]+)</TargetFrameworks>")
    if frameworks then
        local first = frameworks:match("^([^;]+)")
        if first then
            return first:gsub("%s+", "")
        end
    end

    return nil
end

function M.get_framework_display(framework)
    if not framework then
        return "unknown"
    end

    local mappings = {
        ["net8.0"] = ".NET 8",
        ["net7.0"] = ".NET 7",
        ["net6.0"] = ".NET 6",
        ["net5.0"] = ".NET 5",
        ["netcoreapp3.1"] = ".NET Core 3.1",
        ["netstandard2.1"] = ".NET Standard 2.1",
        ["netstandard2.0"] = ".NET Standard 2.0",
        ["net472"] = ".NET Framework 4.7.2",
        ["net471"] = ".NET Framework 4.7.1",
        ["net47"] = ".NET Framework 4.7",
        ["net462"] = ".NET Framework 4.6.2",
        ["net461"] = ".NET Framework 4.6.1",
        ["net46"] = ".NET Framework 4.6",
        ["net452"] = ".NET Framework 4.5.2",
        ["net451"] = ".NET Framework 4.5.1",
        ["net45"] = ".NET Framework 4.5"
    }

    return mappings[framework] or framework
end

return M

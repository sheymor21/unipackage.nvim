local M = {}

-- Import optimized utilities
local http = require("unipackage.utils.http")
local cache = require("unipackage.utils.cache")
local nuget_config = require("unipackage.utils.nuget_config")

local CACHE_DURATION = 30 * 60 -- 30 minutes in seconds

-- Default fallback to nuget.org
local DEFAULT_NUGET_SOURCE = {
    name = "nuget.org",
    url = "https://api.nuget.org/v3/index.json"
}

-- Get enabled package sources from nuget.config or fallback to nuget.org
function M.get_package_sources()
    local sources = nuget_config.get_package_sources()
    if sources and #sources > 0 then
        return sources
    end
    return {DEFAULT_NUGET_SOURCE}
end

-- Helper to sanitize strings for display
local function sanitize(str)
    if not str then return "" end
    str = tostring(str)
    -- Replace newlines with spaces
    str = str:gsub("[\r\n]+", " ")
    -- Trim to reasonable length
    if #str > 200 then
        str = str:sub(1, 197) .. "..."
    end
    return str
end

-- Debug function to trace search issues
function M.debug_search(query)
    query = query or "test"
    local lines = {"NuGet Search Debug", string.rep("=", 50), ""}

    -- Check sources
    local sources = M.get_package_sources()
    table.insert(lines, "Package Sources:")
    for _, source in ipairs(sources) do
        local has_creds = source.credentials and "✓" or "✗"
        table.insert(lines, string.format("  • %s (auth: %s)", source.name, has_creds))
        table.insert(lines, string.format("    URL: %s", source.url))
        if source.credentials then
            table.insert(lines, string.format("    User: %s", source.credentials.username))
        end
    end
    table.insert(lines, "")

    -- Test search on each source
    table.insert(lines, "Testing search for: '" .. query .. "'")
    table.insert(lines, "")

    for _, source in ipairs(sources) do
        table.insert(lines, "Source: " .. source.name)

        -- Test service index directly
        local service_index_url = nuget_config.get_service_index_url(source.url)
        table.insert(lines, "  Service Index URL: " .. service_index_url)

        local headers = nil
        if source.credentials then
            -- Debug: show what credentials we're using
            table.insert(lines, "  Credentials User: " .. (source.credentials.username or "nil"))
            table.insert(lines, "  Credentials Pass: " .. (source.credentials.password and string.sub(source.credentials.password, 1, 10) or "nil") .. "...")
            
            headers = nuget_config.get_auth_headers(source)
            -- Debug: show Authorization header (masked)
            if headers and headers["Authorization"] then
                local auth = headers["Authorization"]
                -- Show first 30 chars of the encoded part
                local prefix = auth:sub(1, 35)
                table.insert(lines, "  Auth Header: " .. prefix .. "...")
            end
        end

        local index_data, index_err = http.get_sync(service_index_url, {headers = headers})        if index_err then
            table.insert(lines, "  Service Index Result: ✗ ERROR - " .. sanitize(index_err))
        elseif index_data and index_data.resources then
            table.insert(lines, "  Service Index Result: ✓ Success (" .. #index_data.resources .. " resources)")

            -- Find search service
            local search_url = nil
            for _, resource in ipairs(index_data.resources) do
                if resource["@type"] and resource["@type"]:match("^SearchQueryService") then                    search_url = resource["@id"]
                    break
                end
            end

            if search_url then
                table.insert(lines, "  Search Service URL: " .. search_url)

                -- Test search
                local encoded_query = query:gsub(" ", "+")
                local search_full_url = string.format("%s?q=%s&take=5&prerelease=false", search_url, encoded_query)
                table.insert(lines, "  Search URL: " .. search_full_url)

                local search_data, search_err = http.get_sync(search_full_url, {headers = headers})
                if search_err then
                    table.insert(lines, "  Search Result: ✗ ERROR - " .. sanitize(search_err))
                elseif search_data and search_data.data then
                    table.insert(lines, "  Search Result: ✓ Success (" .. #search_data.data .. " packages)")
                else
                    table.insert(lines, "  Search Result: ? Unknown response")
                end
            else
                table.insert(lines, "  Search Service URL: ✗ NOT FOUND in service index")
            end
        elseif index_data then
            -- Check if this is an Azure DevOps error response
            if index_data.message or index_data.typeKey or index_data.errorCode then
                table.insert(lines, "  Service Index Result: ✗ AZURE ERROR")
                if index_data.message then
                    table.insert(lines, "    Message: " .. sanitize(index_data.message))
                end
                if index_data.typeName then
                    table.insert(lines, "    Type: " .. sanitize(index_data.typeName))
                end
                if index_data.errorCode then
                    table.insert(lines, "    Code: " .. tostring(index_data.errorCode))
                end
            else
                table.insert(lines, "  Service Index Result: ? Unexpected format")
                -- Show what we got
                if index_data.version then
                    table.insert(lines, "    Version: " .. tostring(index_data.version))
                end
                if index_data["@type"] then
                    table.insert(lines, "    Type: " .. tostring(index_data["@type"]))
                end
                local keys = {}
                for k, _ in pairs(index_data) do table.insert(keys, k) end
                table.insert(lines, "    Keys: " .. table.concat(keys, ", "))
            end
        else
            table.insert(lines, "  Service Index Result: ? No data returned")
        end
        table.insert(lines, "")
    end

    -- Show in floating window
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"

    local width = 85
    local height = math.min(#lines + 2, vim.o.lines - 4)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " NuGet Search Debug ",
    })

    vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, {buffer = buf})
    vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, {buffer = buf})
end

function M.get_search_service_url(source, callback)
    local source_url = type(source) == "string" and source or source.url
    local cache_key = "nuget:search_service_url:" .. source_url
    local cached_url, found = cache.get(cache_key)
    if found and cached_url then
        if callback then
            callback(cached_url)
        else
            return cached_url
        end
        return
    end

    local service_index_url = nuget_config.get_service_index_url(source_url)
    local headers = nil
    if type(source) == "table" and source.credentials then
        headers = nuget_config.get_auth_headers(source)
    end
    
    if callback then
        -- Async version
        http.get(service_index_url, function(success, data, error)
            if not success then
                vim.notify("Failed to get NuGet service URL for " .. source_url .. ": " .. (error or "Unknown error"), vim.log.levels.WARN)
                callback(nil)
                return
            end

            local search_url = nil
            if data and data.resources then
                for _, resource in ipairs(data.resources) do
                    if resource["@type"] and resource["@type"]:match("^SearchQueryService") then
                        search_url = resource["@id"]
                        break
                    end
                end
            end

            if search_url then
                cache.set(cache_key, search_url, 24 * 60 * 60)
            end
            callback(search_url)
        end, {headers = headers})
    else
        -- Sync fallback
        local data, error = http.get_sync(service_index_url, {headers = headers})
        if error then
            vim.notify("Failed to get NuGet service URL: " .. error, vim.log.levels.WARN)
            return nil
        end

        local search_url = nil
        if data and data.resources then
            for _, resource in ipairs(data.resources) do
                if resource["@type"] and resource["@type"]:match("^SearchQueryService") then
                    search_url = resource["@id"]
                    break
                end
            end
        end

        if search_url then
            cache.set(cache_key, search_url, 24 * 60 * 60)
        end
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

function M.parse_search_response(data, source_name)
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
            verified = pkg.verified or false,
            source = source_name
        })
    end

    return results
end

-- Merge results from multiple sources, removing duplicates
function M.merge_results(all_results)
    local seen = {}
    local merged = {}
    
    for _, source_results in ipairs(all_results) do
        for _, pkg in ipairs(source_results) do
            if not seen[pkg.id] then
                seen[pkg.id] = true
                table.insert(merged, pkg)
            end
        end
    end
    
    -- Sort by downloads (popularity)
    table.sort(merged, function(a, b)
        return (a.downloads or 0) > (b.downloads or 0)
    end)
    
    return merged
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

    local sources = M.get_package_sources()
    local all_results = {}
    local pending = #sources
    local has_error = false

    if pending == 0 then
        callback({}, "No package sources configured")
        return
    end

    local function check_complete()
        pending = pending - 1
        if pending == 0 then
            local merged = M.merge_results(all_results)
            if #merged > 0 then
                M.cache_search(query, framework, merged)
                callback(merged, nil)
            elseif has_error then
                callback({}, "Failed to search all package sources")
            else
                callback({}, nil)
            end
        end
    end

    for _, source in ipairs(sources) do
        M.get_search_service_url(source, function(search_url)
            if not search_url then
                has_error = true
                check_complete()
                return
            end

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

            local headers = nil
            if source.credentials then
                headers = nuget_config.get_auth_headers(source)
            end

            http.get(url, function(success, data, error)
                if success then
                    local results = M.parse_search_response(data, source.name)
                    table.insert(all_results, results)
                else
                    has_error = true
                end
                check_complete()
            end, {headers = headers})
        end)
    end
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

    local sources = M.get_package_sources()
    local all_results = {}

    for _, source in ipairs(sources) do
        local search_url = M.get_search_service_url(source)
        if not search_url then
            goto continue
        end

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

        local headers = nil
        if source.credentials then
            headers = nuget_config.get_auth_headers(source)
        end

        local data, error = http.get_sync(url, {headers = headers})
        if not error then
            local results = M.parse_search_response(data, source.name)
            table.insert(all_results, results)
        end

        ::continue::
    end

    local merged = M.merge_results(all_results)
    if #merged > 0 then
        M.cache_search(query, framework, merged)
    end

    return merged
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

    local source_str = ""
    if pkg.source and pkg.source ~= "nuget.org" then
        source_str = string.format(" [%s]", pkg.source)
    end

    local desc = pkg.description or ""
    if #desc > 50 then
        desc = desc:sub(1, 47) .. "..."
    end

    return string.format("%s%s%s%s - %s", id_version, downloads_str, verified_str, source_str, desc)
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
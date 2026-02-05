local M = {}

local CACHE_FILE = vim.fn.stdpath('cache') .. '/unipackage_search_cache.json'
local CACHE_DURATION = 30 * 60 -- 30 minutes in seconds

function M.get_search_service_url()
    local service_index_url = "https://api.nuget.org/v3/index.json"
    local cmd = string.format("curl -s -m 5 '%s'", service_index_url)

    local handle = io.popen(cmd)
    if not handle then
        return "https://api-v2v3search-0.nuget.org/query"
    end

    local response = handle:read("*a")
    handle:close()

    local ok, data = pcall(vim.fn.json_decode, response)
    if not ok or not data or not data.resources then
        return "https://api-v2v3search-0.nuget.org/query"
    end

    for _, resource in ipairs(data.resources) do
        if resource["@type"] and resource["@type"]:match("^SearchQueryService") then
            return resource["@id"]
        end
    end

    return "https://api-v2v3search-0.nuget.org/query"
end

local function load_cache()
    local file = io.open(CACHE_FILE, "r")
    if not file then
        return {}
    end

    local content = file:read("*a")
    file:close()

    local ok, data = pcall(vim.fn.json_decode, content)
    if ok and data then
        return data
    end

    return {}
end

local function save_cache(data)
    local ok, encoded = pcall(vim.fn.json_encode, data)
    if not ok then
        return
    end

    local file = io.open(CACHE_FILE, "w")
    if file then
        file:write(encoded)
        file:close()
    end
end

function M.get_cached_search(query, framework)
    local cache = load_cache()
    local key = string.format("nuget:%s-%s", query, framework or "any")

    if cache[key] then
        local age = os.time() - cache[key].timestamp
        if age < CACHE_DURATION then
            return cache[key].results
        end
    end

    return nil
end

function M.cache_search(query, framework, results)
    local cache = load_cache()
    local key = string.format("nuget:%s-%s", query, framework or "any")

    cache[key] = {
        timestamp = os.time(),
        results = results,
        framework = framework
    }

    if math.random(10) == 1 then
        M.clear_expired_cache(cache)
    end

    save_cache(cache)
end

function M.clear_expired_cache(cache)
    cache = cache or load_cache()
    local now = os.time()
    local cleaned = {}

    for key, entry in pairs(cache) do
        local age = now - entry.timestamp
        if age < CACHE_DURATION then
            cleaned[key] = entry
        end
    end

    save_cache(cleaned)
end

function M.parse_search_response(response)
    local results = {}

    local ok, data = pcall(vim.fn.json_decode, response)
    if not ok or not data or not data.data then
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

    local cmd = string.format("curl -s -m 10 '%s'", url)
    local handle = io.popen(cmd)
    if not handle then
        vim.notify("Failed to execute NuGet search request", vim.log.levels.ERROR)
        return {}
    end

    local response = handle:read("*a")
    handle:close()

    local results = M.parse_search_response(response)

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

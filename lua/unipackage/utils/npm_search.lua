local M = {}

local CACHE_FILE = vim.fn.stdpath('cache') .. '/unipackage_search_cache.json'
local CACHE_DURATION = 30 * 60 -- 30 minutes in seconds

--- Get registry URL for a specific package manager
-- @param manager string: package manager name (npm, yarn, pnpm, bun)
-- @return string: registry URL
function M.get_registry_for_manager(manager)
    local registry_cmd = {
        npm = "npm config get registry",
        yarn = "yarn config get registry",
        pnpm = "pnpm config get registry",
        bun = "npm config get registry" -- Bun uses npm config
    }

    local cmd = registry_cmd[manager]
    if not cmd then
        return "https://registry.npmjs.org"
    end

    local handle = io.popen(cmd .. " 2>/dev/null")
    if not handle then
        return "https://registry.npmjs.org"
    end

    local registry = handle:read("*l")
    handle:close()

    if not registry or registry == "" or registry == "undefined" then
        registry = "https://registry.npmjs.org"
    end

    -- Remove trailing slash
    registry = registry:gsub("/$", "")

    return registry
end

--- Load cache from disk
-- @return table: cached data or empty table
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

--- Save cache to disk
-- @param data table: cache data to save
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

--- Get cached search results if not expired
-- @param query string: search query
-- @param registry string: registry URL
-- @return table|nil: cached results or nil if expired/not found
function M.get_cached_search(query, registry)
    local cache = load_cache()
    local key = query .. "@@" .. registry

    if cache[key] then
        local age = os.time() - cache[key].timestamp
        if age < CACHE_DURATION then
            return cache[key].results
        end
    end

    return nil
end

--- Cache search results
-- @param query string: search query
-- @param registry string: registry URL
-- @param results table: search results to cache
function M.cache_search(query, registry, results)
    local cache = load_cache()
    local key = query .. "@@" .. registry

    cache[key] = {
        timestamp = os.time(),
        results = results,
        registry = registry
    }

    -- Clean expired entries periodically (1 in 10 chance)
    if math.random(10) == 1 then
        M.clear_expired_cache(cache)
    end

    save_cache(cache)
end

--- Clear expired cache entries
-- @param cache table|nil: optional existing cache data
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

--- Parse npm search API response
-- @param response string: JSON response from npm registry
-- @return table: parsed package results
function M.parse_search_response(response)
    local results = {}

    local ok, data = pcall(vim.fn.json_decode, response)
    if not ok or not data or not data.objects then
        return results
    end

    for _, obj in ipairs(data.objects) do
        if obj.package then
            local pkg = obj.package
            local downloads = 0

            -- Extract download count if available
            if obj.score and obj.score.detail and obj.score.detail.popularity then
                downloads = math.floor(obj.score.detail.popularity * 1000000)
            end

            table.insert(results, {
                name = pkg.name,
                version = pkg.version,
                description = pkg.description or "",
                downloads = downloads,
                popularity = obj.score and obj.score.detail and obj.score.detail.popularity or 0
            })
        end
    end

    return results
end

--- Search npm registry for packages
-- @param query string: search query
-- @param manager string: package manager name
-- @param limit number: maximum results (default 20)
-- @return table: search results
function M.search_packages(query, manager, limit)
    limit = limit or 20
    local registry = M.get_registry_for_manager(manager)

    -- Check cache first
    local cached = M.get_cached_search(query, registry)
    if cached then
        return cached
    end

    -- Build search URL
    local encoded_query = query:gsub(" ", "+")
    local url = string.format(
        "%s/-/v1/search?text=%s&size=%d&popularity=1.0",
        registry,
        encoded_query,
        limit
    )

    -- Make HTTP request using curl
    local cmd = string.format("curl -s -m 10 '%s'", url)
    local handle = io.popen(cmd)
    if not handle then
        vim.notify("Failed to execute search request", vim.log.levels.ERROR)
        return {}
    end

    local response = handle:read("*a")
    handle:close()

    -- Parse response
    local results = M.parse_search_response(response)

    -- Cache results
    if #results > 0 then
        M.cache_search(query, registry, results)
    end

    return results
end

--- Format package result for display
-- @param pkg table: package data
-- @return string: formatted display string
function M.format_search_result(pkg)
    local name_version = string.format("%s @ %s", pkg.name, pkg.version)

    -- Format downloads
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

    -- Truncate description
    local desc = pkg.description or ""
    if #desc > 60 then
        desc = desc:sub(1, 57) .. "..."
    end

    return string.format("%s%s - %s", name_version, downloads_str, desc)
end

--- Check if input should trigger search mode
-- @param input string: user input
-- @return boolean: true if should search
function M.is_search_query(input)
    -- Not a search if:
    -- 1. Empty
    -- 2. Contains @ (version specified or @latest)
    -- 3. Contains spaces (multiple packages)
    -- 4. Starts with . or / (local path)

    if not input or input:match("^%s*$") then
        return false
    end

    -- If contains @, it's direct install (react@18.2.0 or react@)
    if input:match("@") then
        return false
    end

    if input:match(" ") then
        return false
    end

    if input:match("^[./]") then
        return false
    end

    return true
end

return M

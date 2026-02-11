local M = {}

local constants = require("unipackage.core.constants")

-- Configuration
local MAX_CACHE_SIZE = constants.MAX_CACHE_SIZE
local MAX_CACHE_MEMORY = constants.MAX_CACHE_MEMORY
local DEFAULT_TTL = constants.CACHE_DURATION
local CLEANUP_INTERVAL = 5 * 60 -- 5 minutes
local PERSIST_INTERVAL = 10 * 60 -- 10 minutes

-- In-memory cache storage
local memory_cache = {}
local cache_order = {} -- LRU: most recent at end
local cache_memory = 0
local last_cleanup = 0
local last_persist = 0

-- Index for O(1) LRU updates
local order_index = {}

-- Cache file path
local CACHE_FILE = vim.fn.stdpath('cache') .. '/unipackage_cache.json'

--- Estimate memory usage of a value
-- @param value any: value to estimate
-- @return number: estimated size in bytes
local function estimate_size(value)
    if type(value) == "string" then
        return #value
    elseif type(value) == "table" then
        local size = 100 -- Table overhead
        for k, v in pairs(value) do
            size = size + estimate_size(k) + estimate_size(v)
        end
        return size
    else
        return 50 -- Estimate for other types
    end
end

--- Remove entry from LRU tracking (O(1))
-- @param key string: cache key
local function remove_from_order(key)
    local idx = order_index[key]
    if not idx then
        return
    end

    -- Remove from array
    table.remove(cache_order, idx)

    -- Update indices for shifted elements
    for i = idx, #cache_order do
        order_index[cache_order[i]] = i
    end

    order_index[key] = nil
end

--- Add entry to end of LRU (most recent)
-- @param key string: cache key
local function add_to_order(key)
    remove_from_order(key) -- Remove if exists
    table.insert(cache_order, key)
    order_index[key] = #cache_order
end

--- Evict oldest entries
-- @param target_bytes number|nil: bytes to free
-- @param target_count number|nil: entries to remove
local function evict_oldest(target_bytes, target_count)
    local freed = 0
    local removed = 0
    local to_remove = {}

    -- Collect oldest entries (from beginning of array)
    for i = 1, #cache_order do
        local key = cache_order[i]
        local entry = memory_cache[key]

        if entry then
            table.insert(to_remove, key)
            freed = freed + entry.size
            removed = removed + 1

            if target_bytes and freed >= target_bytes then
                break
            end
            if target_count and removed >= target_count then
                break
            end
        end
    end

    -- Remove entries
    for _, key in ipairs(to_remove) do
        local entry = memory_cache[key]
        if entry then
            memory_cache[key] = nil
            cache_memory = cache_memory - entry.size
            remove_from_order(key)
        end
    end
end

--- Clean up expired entries
local function cleanup_expired()
    local now = os.time()
    local to_remove = {}

    for key, entry in pairs(memory_cache) do
        if entry.expires_at and now >= entry.expires_at then
            table.insert(to_remove, key)
            cache_memory = cache_memory - entry.size
        end
    end

    for _, key in ipairs(to_remove) do
        memory_cache[key] = nil
        remove_from_order(key)
    end

    last_cleanup = now
end

--- Check if cache needs cleanup
local function maybe_cleanup()
    local now = os.time()

    -- Clean expired entries periodically
    if now - last_cleanup >= CLEANUP_INTERVAL then
        cleanup_expired()
    end

    -- Enforce size limits
    if #cache_order > MAX_CACHE_SIZE then
        evict_oldest(nil, #cache_order - MAX_CACHE_SIZE)
    end

    if cache_memory > MAX_CACHE_MEMORY then
        evict_oldest(cache_memory - MAX_CACHE_MEMORY)
    end
end

--- Persist cache to disk
local function persist_to_disk()
    local data = {
        cache = memory_cache,
        order = cache_order,
        saved_at = os.time()
    }

    local ok, encoded = pcall(vim.fn.json_encode, data)
    if not ok then
        return false
    end

    local file = io.open(CACHE_FILE, "w")
    if not file then
        return false
    end

    file:write(encoded)
    file:close()

    last_persist = os.time()
    return true
end

--- Load cache from disk
local function load_from_disk()
    local file = io.open(CACHE_FILE, "r")
    if not file then
        return
    end

    local content = file:read("*a")
    file:close()

    local ok, data = pcall(vim.fn.json_decode, content)
    if not ok or not data then
        return
    end

    memory_cache = data.cache or {}
    cache_order = data.order or {}

    -- Rebuild index
    order_index = {}
    for i, key in ipairs(cache_order) do
        order_index[key] = i
    end

    -- Recalculate memory
    cache_memory = 0
    for key, entry in pairs(memory_cache) do
        if entry.size then
            cache_memory = cache_memory + entry.size
        else
            entry.size = estimate_size(entry.data)
            cache_memory = cache_memory + entry.size
        end
    end

    cleanup_expired()
end

--- Get value from cache
-- @param key string: cache key
-- @return any: cached value or nil
-- @return boolean: true if found and valid
function M.get(key)
    local entry = memory_cache[key]
    if not entry then
        return nil, false
    end

    -- Check expiration
    if entry.expires_at and os.time() >= entry.expires_at then
        memory_cache[key] = nil
        cache_memory = cache_memory - entry.size
        remove_from_order(key)
        return nil, false
    end

    -- Update LRU (move to end)
    add_to_order(key)

    return entry.data, true
end

--- Set value in cache
-- @param key string: cache key
-- @param value any: value to cache
-- @param ttl number|nil: TTL in seconds
function M.set(key, value, ttl)
    ttl = ttl or DEFAULT_TTL

    -- Remove existing entry
    local existing = memory_cache[key]
    if existing then
        cache_memory = cache_memory - existing.size
    end

    local size = estimate_size(value)

    local entry = {
        data = value,
        created_at = os.time(),
        expires_at = os.time() + ttl,
        size = size
    }

    memory_cache[key] = entry
    cache_memory = cache_memory + size

    add_to_order(key)

    maybe_cleanup()

    -- Maybe persist
    if os.time() - last_persist >= PERSIST_INTERVAL then
        persist_to_disk()
    end
end

--- Delete value from cache
-- @param key string: cache key
-- @return boolean: true if deleted
function M.delete(key)
    local entry = memory_cache[key]
    if not entry then
        return false
    end

    memory_cache[key] = nil
    cache_memory = cache_memory - entry.size
    remove_from_order(key)

    return true
end

--- Clear all cache entries
function M.clear()
    memory_cache = {}
    cache_order = {}
    order_index = {}
    cache_memory = 0
    last_cleanup = os.time()

    local file = io.open(CACHE_FILE, "w")
    if file then
        file:write("{}")
        file:close()
    end
end

--- Get cache statistics
-- @return table: cache stats
function M.stats()
    local now = os.time()
    local expired = 0

    for _, entry in pairs(memory_cache) do
        if entry.expires_at and now >= entry.expires_at then
            expired = expired + 1
        end
    end

    return {
        entries = #cache_order,
        memory = cache_memory,
        memory_limit = MAX_CACHE_MEMORY,
        entry_limit = MAX_CACHE_SIZE,
        expired = expired,
        last_cleanup = last_cleanup,
        last_persist = last_persist
    }
end

--- Get stats for health check
-- @return table: simplified stats
function M.get_stats()
    return M.stats()
end

--- Force maintenance
function M.maintenance()
    cleanup_expired()
    persist_to_disk()
end

--- Initialize cache
function M.init()
    load_from_disk()
    last_cleanup = os.time()
    last_persist = os.time()
end

-- Auto-initialize
M.init()

return M

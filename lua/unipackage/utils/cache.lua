local M = {}

-- Configuration
local MAX_CACHE_SIZE = 100 -- Maximum number of entries
local MAX_CACHE_MEMORY = 10 * 1024 * 1024 -- 10MB max memory usage
local DEFAULT_TTL = 30 * 60 -- 30 minutes default TTL
local CLEANUP_INTERVAL = 5 * 60 -- 5 minutes between cleanups
local PERSIST_INTERVAL = 10 * 60 -- 10 minutes between disk saves

-- In-memory cache storage
local memory_cache = {}
local cache_order = {} -- For LRU tracking
local cache_memory = 0 -- Track memory usage
local last_cleanup = 0
local last_persist = 0

-- Cache file path
local CACHE_FILE
if vim and vim.fn then
    CACHE_FILE = vim.fn.stdpath('cache') .. '/unipackage_cache.json'
else
    CACHE_FILE = os.getenv("HOME") .. '/.cache/unipackage_cache.json'
end

--- Estimate memory usage of a value
-- @param value any: value to estimate size for
-- @return number: estimated size in bytes
local function estimate_size(value)
    local size = 0
    
    if type(value) == "string" then
        size = #value
    elseif type(value) == "table" then
        -- Rough estimation for tables
        for k, v in pairs(value) do
            size = size + estimate_size(k) + estimate_size(v)
        end
        size = size + 100 -- Overhead for table structure
    else
        size = 50 -- Rough estimate for other types
    end
    
    return size
end

--- Remove oldest entries to free memory
-- @param target_size number: target memory size to free
local function evict_oldest(target_size)
    local freed = 0
    local to_remove = {}
    
    -- Collect oldest entries
    for i = #cache_order, 1, -1 do
        local key = cache_order[i]
        if memory_cache[key] then
            local entry = memory_cache[key]
            table.insert(to_remove, key)
            freed = freed + entry.size
            cache_memory = cache_memory - entry.size
            
            if target_size and freed >= target_size then
                break
            end
        end
    end
    
    -- Remove entries
    for _, key in ipairs(to_remove) do
        memory_cache[key] = nil
        -- Remove from order tracking
        for i, k in ipairs(cache_order) do
            if k == key then
                table.remove(cache_order, i)
                break
            end
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
        -- Remove from order tracking
        for i, k in ipairs(cache_order) do
            if k == key then
                table.remove(cache_order, i)
                break
            end
        end
    end
    
    last_cleanup = now
end

--- Check if cache needs cleanup
local function maybe_cleanup()
    local now = os.time()
    
    -- Clean expired entries
    if now - last_cleanup >= CLEANUP_INTERVAL then
        cleanup_expired()
    end
    
    -- Enforce size limits
    if #cache_order > MAX_CACHE_SIZE then
        evict_oldest(#cache_order - MAX_CACHE_SIZE + 1)
    end
    
    if cache_memory > MAX_CACHE_MEMORY then
        evict_oldest(cache_memory - MAX_CACHE_MEMORY + 1)
    end
end

--- Persist cache to disk
local function persist_to_disk()
    local data = {
        cache = memory_cache,
        order = cache_order,
        saved_at = os.time()
    }
    
    local ok, encoded
    if vim and vim.fn then
        ok, encoded = pcall(vim.fn.json_encode, data)
    else
        ok, encoded = pcall(function(d) return require('json').encode(d) end, data)
    end
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
    
    local ok, data
    if vim and vim.fn then
        ok, data = pcall(vim.fn.json_decode, content)
    else
        ok, data = pcall(function(c) return require('json').decode(c) end, content)
    end
    if not ok or not data then
        return
    end
    
    -- Restore cache data
    memory_cache = data.cache or {}
    cache_order = data.order or {}
    
    -- Recalculate memory usage
    cache_memory = 0
    for key, entry in pairs(memory_cache) do
        if entry.size then
            cache_memory = cache_memory + entry.size
        else
            -- Recalculate size for entries without size info
            entry.size = estimate_size(entry.data)
            cache_memory = cache_memory + entry.size
        end
    end
    
    -- Clean expired entries on load
    cleanup_expired()
end

--- Get value from cache
-- @param key string: cache key
-- @return any: cached value or nil
-- @return boolean: true if value was found and not expired
function M.get(key)
    local entry = memory_cache[key]
    if not entry then
        return nil, false
    end
    
    -- Check expiration
    if entry.expires_at and os.time() >= entry.expires_at then
        -- Remove expired entry
        memory_cache[key] = nil
        cache_memory = cache_memory - entry.size
        for i, k in ipairs(cache_order) do
            if k == key then
                table.remove(cache_order, i)
                break
            end
        end
        return nil, false
    end
    
    -- Update LRU order (move to end)
    for i, k in ipairs(cache_order) do
        if k == key then
            table.remove(cache_order, i)
            table.insert(cache_order, key)
            break
        end
    end
    
    return entry.data, true
end

--- Set value in cache
-- @param key string: cache key
-- @param value any: value to cache
-- @param ttl number|nil: time to live in seconds (default: 30 minutes)
function M.set(key, value, ttl)
    ttl = ttl or DEFAULT_TTL
    
    -- Remove existing entry if present
    local existing_entry = memory_cache[key]
    if existing_entry then
        cache_memory = cache_memory - existing_entry.size
    end
    
    -- Calculate size
    local size = estimate_size(value)
    
    -- Create new entry
    local entry = {
        data = value,
        created_at = os.time(),
        expires_at = os.time() + ttl,
        size = size
    }
    
    memory_cache[key] = entry
    cache_memory = cache_memory + size
    
    -- Update LRU order
    for i, k in ipairs(cache_order) do
        if k == key then
            table.remove(cache_order, i)
            break
        end
    end
    table.insert(cache_order, key)
    
    -- Check if we need to cleanup
    maybe_cleanup()
    
    -- Maybe persist to disk
    local now = os.time()
    if now - last_persist >= PERSIST_INTERVAL then
        persist_to_disk()
    end
end

--- Delete value from cache
-- @param key string: cache key
-- @return boolean: true if entry was deleted
function M.delete(key)
    local entry = memory_cache[key]
    if not entry then
        return false
    end
    
    memory_cache[key] = nil
    cache_memory = cache_memory - entry.size
    
    -- Remove from order tracking
    for i, k in ipairs(cache_order) do
        if k == key then
            table.remove(cache_order, i)
            break
        end
    end
    
    return true
end

--- Clear all cache entries
function M.clear()
    memory_cache = {}
    cache_order = {}
    cache_memory = 0
    last_cleanup = os.time()
    
    -- Also clear disk cache
    local file = io.open(CACHE_FILE, "w")
    if file then
        file:write("{}")
        file:close()
    end
end

--- Get cache statistics
-- @return table: statistics about cache usage
function M.stats()
    local now = os.time()
    local expired_count = 0
    
    for _, entry in pairs(memory_cache) do
        if entry.expires_at and now >= entry.expires_at then
            expired_count = expired_count + 1
        end
    end
    
    return {
        total_entries = #cache_order,
        memory_usage = cache_memory,
        memory_limit = MAX_CACHE_MEMORY,
        entry_limit = MAX_CACHE_SIZE,
        expired_entries = expired_count,
        last_cleanup = last_cleanup,
        last_persist = last_persist
    }
end

--- Force cleanup and persist
function M.maintenance()
    cleanup_expired()
    persist_to_disk()
end

--- Initialize cache (load from disk)
function M.init()
    load_from_disk()
    last_cleanup = os.time()
    last_persist = os.time()
end

-- Auto-initialize
M.init()

return M
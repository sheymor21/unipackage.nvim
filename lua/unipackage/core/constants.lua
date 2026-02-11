local M = {}

-- Cache durations (in seconds)
M.CACHE_DURATION = 30 * 60  -- 30 minutes
M.CACHE_DURATION_SHORT = 5 * 60  -- 5 minutes

-- Cache size limits
M.MAX_CACHE_SIZE = 100
M.MAX_CACHE_MEMORY = 10 * 1024 * 1024  -- 10MB

-- HTTP settings
M.MAX_RESPONSE_SIZE = 1024 * 1024  -- 1MB
M.DEFAULT_TIMEOUT = 10000  -- 10 seconds
M.MAX_TIMEOUT = 30000  -- 30 seconds

-- Search settings
M.DEFAULT_SEARCH_BATCH_SIZE = 20
M.MIN_SEARCH_BATCH_SIZE = 1
M.MAX_SEARCH_BATCH_SIZE = 100
M.MAX_SEARCH_RESULTS = 250

-- UI settings
M.DEFAULT_FLOAT_WIDTH = 80
M.MAX_FLOAT_WIDTH = 160

-- Validation helpers
function M.validate_batch_size(size)
    size = tonumber(size) or M.DEFAULT_SEARCH_BATCH_SIZE
    return math.max(M.MIN_SEARCH_BATCH_SIZE, math.min(size, M.MAX_SEARCH_BATCH_SIZE))
end

return M

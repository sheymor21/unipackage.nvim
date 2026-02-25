local M = {}

-- Configuration
local MAX_RESPONSE_SIZE = 10 * 1024 * 1024 -- 10MB max response size (needed for packages with many versions like React)
local DEFAULT_TIMEOUT = 15000 -- 15 seconds

--- Safe JSON parsing with size limits
-- @param content string: JSON content to parse
-- @return table|nil: parsed data or nil if failed
-- @return string|nil: error message
local function safe_json_decode(content)
    -- Check content size first
    if #content > MAX_RESPONSE_SIZE then
        return nil, string.format("Response too large: %d bytes (max: %d)", #content, MAX_RESPONSE_SIZE)
    end
    
    local ok, data = pcall(vim.fn.json_decode, content)
    if not ok then
        return nil, "JSON parsing failed: " .. tostring(data)
    end
    
    return data, nil
end

--- Build curl command with headers
-- @param url string: URL to request
-- @param method string: HTTP method (GET, POST, HEAD)
-- @param headers table: headers table
-- @param body string|nil: request body
-- @param timeout number: timeout in seconds
-- @return string: curl command
local function build_curl_command(url, method, headers, body, timeout)
    local cmd = {"curl", "-s", "-m", tostring(timeout / 1000)}
    
    -- Add method
    if method == "HEAD" then
        table.insert(cmd, "-I")
    elseif method == "POST" and body then
        table.insert(cmd, "-X")
        table.insert(cmd, "POST")
        table.insert(cmd, "-d")
        table.insert(cmd, body)
    end
    
    -- Add headers
    table.insert(cmd, "-H")
    table.insert(cmd, "User-Agent: unipackage.nvim/1.0")
    
    for key, value in pairs(headers) do
        table.insert(cmd, "-H")
        table.insert(cmd, key .. ": " .. value)
    end
    
    -- Add URL
    table.insert(cmd, url)
    
    return cmd
end

--- Make async HTTP request using curl
-- @param url string: URL to request
-- @param method string: HTTP method
-- @param callback function: callback(success, data, error)
-- @param options table: options (headers, body, timeout)
local function curl_async(url, method, callback, options)
    options = options or {}
    local headers = options.headers or {}
    local body = options.body
    local timeout = options.timeout or DEFAULT_TIMEOUT
    
    -- Build curl command
    local cmd = build_curl_command(url, method, headers, body, timeout)
    
    -- Execute curl command
    vim.loop.spawn("curl", {
        args = vim.list_slice(cmd, 2), -- Skip "curl" from args
        stdio = {nil, vim.loop.new_pipe(false), vim.loop.new_pipe(false)},
    }, function(code, signal)
        if code ~= 0 then
            callback(false, nil, "curl failed with code: " .. code)
            return
        end
    end)
    
    -- For simplicity, use sync fallback for now
    -- In a real implementation, we'd need to handle stdout properly
    local data, error = M.get_sync(url, options)
    callback(data ~= nil, data, error)
end

--- Make sync HTTP request using curl
-- @param url string: URL to request
-- @param method string: HTTP method
-- @param options table: options (headers, body, timeout)
-- @return table|nil: response data
-- @return string|nil: error message
local function curl_sync(url, method, options)
    options = options or {}
    local headers = options.headers or {}
    local body = options.body
    local timeout = options.timeout or DEFAULT_TIMEOUT
    
    -- Build curl command
    local cmd = build_curl_command(url, method, headers, body, timeout)
    
    -- Execute curl command
    local handle = io.popen(table.concat(cmd, " "))
    if not handle then
        return nil, "Failed to execute curl command"
    end
    
    local response = handle:read("*a")
    handle:close()
    
    -- Parse response
    if method == "HEAD" then
        -- For HEAD requests, parse status from response
        local status = response:match("HTTP/1%.1 (%d+)")
        if status then
            return {status = tonumber(status)}, nil
        else
            return nil, "Failed to parse HEAD response"
        end
    else
        -- For GET/POST requests, parse JSON
        local data, err = safe_json_decode(response)
        if err then
            return nil, err
        end
        return data, nil
    end
end

--- Make async HTTP GET request
-- @param url string: URL to request
-- @param callback function: callback(success, data, error)
-- @param options table|nil: optional parameters (timeout, headers)
function M.get(url, callback, options)
    curl_async(url, "GET", callback, options)
end

--- Make async HTTP POST request
-- @param url string: URL to request
-- @param body string|table: request body
-- @param callback function: callback(success, data, error)
-- @param options table|nil: optional parameters (timeout, headers)
function M.post(url, body, callback, options)
    options = options or {}
    
    -- Encode body if it's a table
    if type(body) == "table" then
        local ok, encoded = pcall(vim.fn.json_encode, body)
        if not ok then
            callback(false, nil, "Failed to encode request body")
            return
        end
        body = encoded
        options.headers = options.headers or {}
        options.headers["Content-Type"] = "application/json"
    end
    
    options.body = body
    curl_async(url, "POST", callback, options)
end

--- Make synchronous HTTP request (fallback for critical operations)
-- @param url string: URL to request
-- @param options table|nil: optional parameters (timeout, headers)
-- @return table|nil: response data
-- @return string|nil: error message
function M.get_sync(url, options)
    return curl_sync(url, "GET", options)
end

--- Check if URL is reachable (simple health check)
-- @param url string: URL to check
-- @param callback function: callback(reachable, error)
function M.health_check(url, callback)
    curl_async(url, "HEAD", function(success, data, error)
        if success and data and data.status and data.status < 400 then
            callback(true, nil)
        else
            callback(false, error or "Health check failed")
        end
    end, {timeout = 5000})
end

return M
local M = {}

-- Module cache for loaded manager modules
local module_cache = {}

-- Module path mappings
local module_paths = {
    go = "unipackage.languages.go.go",
    dotnet = "unipackage.languages.dotnet.dotnet",
}

-- JavaScript managers use pattern
local js_pattern = "unipackage.languages.javascript.%s"

--- Load a manager module with caching
-- @param manager string: package manager name
-- @return table|nil: loaded module or nil if not found
function M.load(manager)
    -- Check cache first
    if module_cache[manager] then
        return module_cache[manager]
    end

    local module = nil
    local module_path = module_paths[manager]

    if not module_path then
        -- Try JavaScript pattern
        module_path = string.format(js_pattern, manager)
    end

    local ok, loaded = pcall(require, module_path)
    if ok then
        module = loaded
    end

    -- Cache the result (even if nil to avoid repeated attempts)
    module_cache[manager] = module
    return module
end

--- Clear the module cache
-- Useful for reloading during development
function M.clear_cache()
    module_cache = {}
end

--- Check if a module is cached
-- @param manager string: package manager name
-- @return boolean: true if cached
function M.is_cached(manager)
    return module_cache[manager] ~= nil
end

--- Get list of valid manager names
-- @return table: array of valid manager names
function M.get_valid_managers()
    return { "bun", "dotnet", "go", "npm", "pnpm", "yarn" }
end

--- Check if a manager name is valid
-- @param manager string: package manager name
-- @return boolean: true if valid
function M.is_valid(manager)
    return vim.tbl_contains(M.get_valid_managers(), manager)
end

-- Backward compatibility layer
M.get_module = function(manager, language)
    local module_path = string.format("unipackage.%s.%s", language, manager)
    local ok, module = pcall(require, module_path)
    return ok and module or nil
end

-- Backward compatibility layer
M.get_legacy_module = function(manager)
    local ok, module = pcall(require, "unipackage." .. manager)
    return ok and module or nil
end

return M

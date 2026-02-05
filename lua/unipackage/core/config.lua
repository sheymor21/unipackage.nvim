local M = {}

-- Default configuration aligned with user preferences
local default_config = {
    -- Package manager priority order (modern → traditional)
    package_managers = {"bun", "pnpm", "npm", "yarn"},
    
    -- Detection settings
    auto_detect = true,
    require_explicit = false,
    
    -- Fallback behavior
    fallback_to_any = true,  -- If no lock file found, use any available manager
    warn_on_fallback = true, -- Show warning when using fallback
    
    -- UI settings
    show_priority_in_menu = true,
    highlight_priority_manager = true,
}

-- Internal configuration state
local config = vim.deepcopy(default_config)

-- Package manager lock file detection patterns
local detection_patterns = {
    bun = {"bun.lock", "bun.lockb"},
    npm = {"package-lock.json"},
    pnpm = {"pnpm-lock.yaml"},
    yarn = {"yarn.lock", ".yarnrc.yml"},
}

-- Validation functions
local function validate_package_manager(name)
    local valid_managers = {"bun", "npm", "pnpm", "yarn"}
    return vim.tbl_contains(valid_managers, name)
end

local function validate_config(user_config)
    local errors = {}
    
    -- Validate package_managers array
    if user_config.package_managers then
        if type(user_config.package_managers) ~= "table" then
            table.insert(errors, "package_managers must be an array")
        else
            for i, manager in ipairs(user_config.package_managers) do
                if not validate_package_manager(manager) then
                    table.insert(errors, string.format(
                        "Invalid package manager at index %d: %s. Valid managers: bun, npm, pnpm, yarn", 
                        i, tostring(manager)
                    ))
                end
            end
        end
    end
    
    -- Validate boolean settings
    local boolean_settings = {"auto_detect", "require_explicit", "fallback_to_any", "warn_on_fallback", "show_priority_in_menu", "highlight_priority_manager"}
    for _, setting in ipairs(boolean_settings) do
        if user_config[setting] ~= nil and type(user_config[setting]) ~= "boolean" then
            table.insert(errors, string.format("%s must be a boolean", setting))
        end
    end
    
    return errors
end

-- Get detected package managers from lock files
local function get_detected_managers()
    local cwd = vim.fn.getcwd()
    local detected = {}
    
    -- Check for lock files
    for manager, patterns in pairs(detection_patterns) do
        for _, pattern in ipairs(patterns) do
            local file_path = cwd .. "/" .. pattern
            local file = vim.uv.fs_stat(file_path)
            if file then
                if not vim.tbl_contains(detected, manager) then
                    table.insert(detected, manager)
                end
                break -- Found a lock file for this manager
            end
        end
    end
    
    return detected
end

-- Priority resolution: Lock files first, then user preference
local function resolve_priority_manager()
    local detected = get_detected_managers()
    
    -- If lock files detected, use user's priority order among detected managers
    if #detected > 0 then
        for _, priority_manager in ipairs(config.package_managers) do
            if vim.tbl_contains(detected, priority_manager) then
                return priority_manager
            end
        end
    end
    
    -- No lock files, fallback to highest priority available manager
    if config.fallback_to_any then
        for _, manager in ipairs(config.package_managers) do
            if vim.fn.executable(manager) == 1 then
                if config.warn_on_fallback then
                    vim.notify(
                        string.format("UniPackage: Using fallback manager '%s' (no project lock file detected)", manager),
                        vim.log.levels.WARN
                    )
                end
                return manager
            end
        end
    end
    
    return nil
end

-- Public API
M.setup = function(user_config)
    user_config = user_config or {}
    
    -- Validate user configuration
    local errors = validate_config(user_config)
    if #errors > 0 then
        local error_msg = "UniPackage configuration errors:\n" .. table.concat(errors, "\n")
        vim.notify(error_msg, vim.log.levels.ERROR)
        return false
    end
    
    -- Merge user config with defaults
    config = vim.tbl_deep_extend("force", default_config, user_config)
    
    -- Store in global variable for external access
    vim.g.unipackage_config = config
    
    return true
end

M.get = function(key)
    if key then
        return config[key]
    end
    return vim.deepcopy(config)
end

M.get_priority_order = function()
    return vim.deepcopy(config.package_managers)
end

M.get_preferred_manager = function()
    return resolve_priority_manager()
end

M.is_manager_available = function(manager)
    -- Check if manager is in priority list
    if not vim.tbl_contains(config.package_managers, manager) then
        return false
    end
    
    -- Check if manager is actually available on the system
    return vim.fn.executable(manager) == 1
end

M.get_detected_managers = function()
    return get_detected_managers()
end

M.get_detection_patterns = function()
    return vim.deepcopy(detection_patterns)
end

return M

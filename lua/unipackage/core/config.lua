local M = {}

-- Default configuration aligned with user preferences
local default_config = {
    -- Package manager priority order (modern → traditional)
    package_managers = {"bun", "go", "dotnet", "pnpm", "npm", "yarn"},
    
    -- Search results configuration
    search_batch_size = 20,  -- Number of items to show per batch in search results
    
    -- Fallback behavior
    fallback_to_any = true,  -- If no lock file found, use any available manager
    warn_on_fallback = true, -- Show warning when using fallback
    

}

-- Internal configuration state
local config = vim.deepcopy(default_config)

-- Language definitions with their package managers and detection files
local languages = {
    dotnet = {
        managers = {"dotnet"},
        files = {"*.sln", "*.csproj", "*.fsproj", "*.vbproj"}
    },
    go = {
        managers = {"go"},
        files = {"go.mod", "go.sum", "go.work"}
    },
    javascript = {
        managers = {"bun", "pnpm", "npm", "yarn"},
        files = {"package.json"}
    }
}

-- Package manager lock file detection patterns
local detection_patterns = {
    bun = {"bun.lock", "bun.lockb"},
    dotnet = {"*.sln", "*.csproj", "*.fsproj", "*.vbproj"},
    go = {"go.mod", "go.sum", "go.work"},
    npm = {"package-lock.json"},
    pnpm = {"pnpm-lock.yaml"},
    yarn = {"yarn.lock", ".yarnrc.yml"},
}

-- Validation functions
local function validate_package_manager(name)
    local valid_managers = {"bun", "dotnet", "go", "npm", "pnpm", "yarn"}
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
                        "Invalid package manager at index %d: %s. Valid managers: bun, dotnet, go, npm, pnpm, yarn",
                        i, tostring(manager)
                    ))
                end
            end
        end
    end
    
    -- Validate boolean settings
    local boolean_settings = {"fallback_to_any", "warn_on_fallback"}
    for _, setting in ipairs(boolean_settings) do
        if user_config[setting] ~= nil and type(user_config[setting]) ~= "boolean" then
            table.insert(errors, string.format("%s must be a boolean", setting))
        end
    end

    -- Validate search_batch_size
    if user_config.search_batch_size ~= nil then
        if type(user_config.search_batch_size) ~= "number" then
            table.insert(errors, "search_batch_size must be a number")
        elseif user_config.search_batch_size < 1 or user_config.search_batch_size > 100 then
            table.insert(errors, "search_batch_size must be between 1 and 100")
        end
    end
    
    return errors
end

-- Detect project language based on language-specific files
local function detect_language()
    local cwd = vim.fn.getcwd()

    for lang, data in pairs(languages) do
        for _, file in ipairs(data.files) do
            -- Check if file pattern contains a wildcard (starts with *.)
            if file:match("^%*") then
                -- Use glob to find matching files
                local pattern = cwd .. "/" .. file
                local files = vim.fn.glob(pattern, false, true)
                if #files > 0 then
                    return lang
                end
            else
                -- Check for exact file match
                local file_path = cwd .. "/" .. file
                local stat = vim.uv.fs_stat(file_path)
                if stat then
                    return lang
                end
            end
        end
    end

    return nil
end

-- Get detected package managers from lock files
local function get_detected_managers()
    local cwd = vim.fn.getcwd()
    local detected = {}

    -- Check for lock files
    for manager, patterns in pairs(detection_patterns) do
        for _, pattern in ipairs(patterns) do
            -- Check if pattern contains a wildcard
            if pattern:match("%*") then
                -- Use glob to find matching files
                local glob_pattern = cwd .. "/" .. pattern
                local files = vim.fn.glob(glob_pattern, false, true)
                if #files > 0 then
                    if not vim.tbl_contains(detected, manager) then
                        table.insert(detected, manager)
                    end
                    break -- Found a lock file for this manager
                end
            else
                -- Check for exact file match
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
    end

    return detected
end

-- Priority resolution: Language-specific detection first, then lock files
local function resolve_priority_manager()
    local detected = get_detected_managers()
    local project_language = detect_language()
    
    -- If we detected a language, only consider managers from that language
    if project_language then
        local lang_data = languages[project_language]
        local lang_managers = lang_data and lang_data.managers or {}
        
        -- Filter detected managers to only those in this language
        local lang_detected = {}
        for _, manager in ipairs(detected) do
            if vim.tbl_contains(lang_managers, manager) then
                table.insert(lang_detected, manager)
            end
        end
        
        -- Use priority order among language-specific managers
        if #lang_detected > 0 then
            for _, priority_manager in ipairs(config.package_managers) do
                if vim.tbl_contains(lang_detected, priority_manager) then
                    return priority_manager
                end
            end
        end
        
        -- Language detected but no lock file found
        if config.fallback_to_any then
            for _, manager in ipairs(config.package_managers) do
                if vim.tbl_contains(lang_managers, manager) and vim.fn.executable(manager) == 1 then
                    if config.warn_on_fallback then
                        vim.notify(
                            string.format("UniPackage: Using fallback manager '%s' for %s project (no lock file detected)", 
                                manager, project_language),
                            vim.log.levels.WARN
                        )
                    end
                    return manager
                end
            end
        else
            -- No fallback allowed - show notification
            vim.notify(
                string.format("UniPackage: No package manager detected for %s project and fallback is disabled", 
                    project_language),
                vim.log.levels.WARN
            )
            return nil
        end
    end
    
    -- No language detected, fall back to original behavior
    if #detected > 0 then
        for _, priority_manager in ipairs(config.package_managers) do
            if vim.tbl_contains(detected, priority_manager) then
                return priority_manager
            end
        end
    end
    
    -- No lock files and no language detected
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
    else
        -- No fallback allowed - show notification
        vim.notify(
            "UniPackage: No package manager detected and fallback is disabled. Please check your project files or enable fallback.",
            vim.log.levels.WARN
        )
    end
    
    return nil
end

-- Silent version of priority resolution (no notifications)
local function resolve_priority_manager_silent()
    local detected = get_detected_managers()
    local project_language = detect_language()
    
    -- If we detected a language, only consider managers from that language
    if project_language then
        local lang_data = languages[project_language]
        local lang_managers = lang_data and lang_data.managers or {}
        
        -- Filter detected managers to only those in this language
        local lang_detected = {}
        for _, manager in ipairs(detected) do
            if vim.tbl_contains(lang_managers, manager) then
                table.insert(lang_detected, manager)
            end
        end
        
        -- Use priority order among language-specific managers
        if #lang_detected > 0 then
            for _, priority_manager in ipairs(config.package_managers) do
                if vim.tbl_contains(lang_detected, priority_manager) then
                    return priority_manager
                end
            end
        end
        
        -- Language detected but no lock file found
        if config.fallback_to_any then
            for _, manager in ipairs(config.package_managers) do
                if vim.tbl_contains(lang_managers, manager) and vim.fn.executable(manager) == 1 then
                    return manager
                end
            end
        end
        -- No fallback allowed - return nil silently
        return nil
    end
    
    -- No language detected, fall back to original behavior
    if #detected > 0 then
        for _, priority_manager in ipairs(config.package_managers) do
            if vim.tbl_contains(detected, priority_manager) then
                return priority_manager
            end
        end
    end
    
    -- No lock files and no language detected
    if config.fallback_to_any then
        for _, manager in ipairs(config.package_managers) do
            if vim.fn.executable(manager) == 1 then
                return manager
            end
        end
    end
    
    -- No fallback allowed - return nil silently
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

M.get_preferred_manager_silent = function()
    return resolve_priority_manager_silent()
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

M.get_detected_language = function()
    return detect_language()
end

return M

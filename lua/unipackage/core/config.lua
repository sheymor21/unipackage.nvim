local M = {}

local constants = require("unipackage.core.constants")
local error_handler = require("unipackage.core.error")

-- Default configuration
local default_config = {
    package_managers = {"bun", "go", "dotnet", "pnpm", "npm", "yarn"},
    search_batch_size = constants.DEFAULT_SEARCH_BATCH_SIZE,
    fallback_to_any = true,
    warn_on_fallback = true,
    version_selection = {
        enabled = false,
        languages = {
            javascript = true,
            dotnet = true,
            go = false,
        },
        include_prerelease = false,
        max_versions_shown = 20,
    },
}

-- Internal configuration state
local config = vim.deepcopy(default_config)

-- Language definitions
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

-- Lock file detection patterns
local detection_patterns = {
    bun = {"bun.lock", "bun.lockb"},
    dotnet = {"*.sln", "*.csproj", "*.fsproj", "*.vbproj"},
    go = {"go.mod", "go.sum", "go.work"},
    npm = {"package-lock.json"},
    pnpm = {"pnpm-lock.yaml"},
    yarn = {"yarn.lock", ".yarnrc.yml"},
}

-- Cache for file detection
local detection_cache = {
    cwd = nil,
    timestamp = nil,
    ttl = 5000, -- 5 seconds
}

--- Check if cache is valid
local function is_cache_valid()
    if not detection_cache.cwd or detection_cache.cwd ~= vim.fn.getcwd() then
        return false
    end
    if not detection_cache.timestamp then
        return false
    end
    return (vim.loop.now() - detection_cache.timestamp) < detection_cache.ttl
end

--- Update detection cache
local function update_cache(key, value)
    detection_cache.cwd = vim.fn.getcwd()
    detection_cache.timestamp = vim.loop.now()
    detection_cache[key] = value
end

--- Check if file pattern matches (handles wildcards)
-- @param pattern string: File pattern (may contain wildcards)
-- @param cwd string: Current working directory
-- @return boolean: true if match found
local function check_file_pattern(pattern, cwd)
    if pattern:match("%*") then
        local glob_pattern = cwd .. "/" .. pattern
        local files = vim.fn.glob(glob_pattern, false, true)
        return #files > 0
    else
        local file_path = cwd .. "/" .. pattern
        return vim.uv.fs_stat(file_path) ~= nil
    end
end

--- Detect project language
-- @return string|nil: detected language or nil
function M.detect_language()
    if is_cache_valid() and detection_cache.language then
        return detection_cache.language
    end

    local cwd = vim.fn.getcwd()

    for lang, data in pairs(languages) do
        for _, file in ipairs(data.files) do
            if check_file_pattern(file, cwd) then
                update_cache("language", lang)
                return lang
            end
        end
    end

    update_cache("language", nil)
    return nil
end

--- Get detected package managers from lock files
-- @return table: array of detected manager names
function M.get_detected_managers()
    if is_cache_valid() and detection_cache.managers then
        return detection_cache.managers
    end

    local cwd = vim.fn.getcwd()
    local detected = {}
    local seen = {}

    for manager, patterns in pairs(detection_patterns) do
        for _, pattern in ipairs(patterns) do
            if check_file_pattern(pattern, cwd) then
                if not seen[manager] then
                    table.insert(detected, manager)
                    seen[manager] = true
                end
                break
            end
        end
    end

    update_cache("managers", detected)
    return detected
end

--- Filter managers by language
-- @param detected table: Array of detected managers
-- @param lang_managers table: Array of valid managers for the language
-- @return table: Filtered managers
local function filter_by_language(detected, lang_managers)
    local filtered = {}
    for _, manager in ipairs(detected) do
        if vim.tbl_contains(lang_managers, manager) then
            table.insert(filtered, manager)
        end
    end
    return filtered
end

--- Find first available manager from priority list
-- @param candidates table: Array of candidate managers
-- @param silent boolean: If true, don't show notifications
-- @return string|nil: First available manager or nil
local function find_first_available(candidates, silent)
    for _, manager in ipairs(candidates) do
        if vim.fn.executable(manager) == 1 then
            return manager
        end
    end
    return nil
end

--- Resolve preferred manager with optional notifications
-- @param silent boolean: If true, don't show notifications
-- @return string|nil: Preferred manager or nil
local function resolve_manager(silent)
    local detected = M.get_detected_managers()
    local project_language = M.detect_language()

    if project_language then
        local lang_data = languages[project_language]
        local lang_managers = lang_data and lang_data.managers or {}

        -- Filter by language
        local lang_detected = filter_by_language(detected, lang_managers)

        -- Use priority order among language-specific managers
        if #lang_detected > 0 then
            for _, priority_manager in ipairs(config.package_managers) do
                if vim.tbl_contains(lang_detected, priority_manager) then
                    return priority_manager
                end
            end
        end

        -- Language detected but no lock file - try fallback
        if config.fallback_to_any then
            local fallback = find_first_available(config.package_managers, silent)
            if fallback and vim.tbl_contains(lang_managers, fallback) then
                if not silent and config.warn_on_fallback then
                    error_handler.handle("config",
                        string.format("Using fallback manager '%s' for %s project (no lock file detected)",
                            fallback, project_language),
                        vim.log.levels.WARN)
                end
                return fallback
            end
        elseif not silent then
            error_handler.handle("config",
                string.format("No package manager detected for %s project and fallback is disabled", project_language),
                vim.log.levels.WARN)
        end
        return nil
    end

    -- No language detected - use lock file priority
    if #detected > 0 then
        for _, priority_manager in ipairs(config.package_managers) do
            if vim.tbl_contains(detected, priority_manager) then
                return priority_manager
            end
        end
    end

    -- No lock files - try global fallback
    if config.fallback_to_any then
        local fallback = find_first_available(config.package_managers, silent)
        if fallback and not silent and config.warn_on_fallback then
            error_handler.handle("config",
                string.format("Using fallback manager '%s' (no project lock file detected)", fallback),
                vim.log.levels.WARN)
        end
        return fallback
    elseif not silent then
        error_handler.handle("config",
            "No package manager detected and fallback is disabled. Please check your project files or enable fallback.",
            vim.log.levels.WARN)
    end

    return nil
end

-- Validation functions
local function validate_package_manager(name)
    return vim.tbl_contains(default_config.package_managers, name)
end

local function validate_config(user_config)
    local errors = {}

    if user_config.package_managers then
        if type(user_config.package_managers) ~= "table" then
            table.insert(errors, "package_managers must be an array")
        else
            for i, manager in ipairs(user_config.package_managers) do
                if not validate_package_manager(manager) then
                    table.insert(errors, string.format(
                        "Invalid package manager at index %d: %s",
                        i, tostring(manager)
                    ))
                end
            end
        end
    end

    local boolean_settings = {"fallback_to_any", "warn_on_fallback"}
    for _, setting in ipairs(boolean_settings) do
        if user_config[setting] ~= nil and type(user_config[setting]) ~= "boolean" then
            table.insert(errors, string.format("%s must be a boolean", setting))
        end
    end

    -- Validate version_selection configuration
    if user_config.version_selection then
        if user_config.version_selection.enabled ~= nil and type(user_config.version_selection.enabled) ~= "boolean" then
            table.insert(errors, "version_selection.enabled must be a boolean")
        end
        if user_config.version_selection.include_prerelease ~= nil and type(user_config.version_selection.include_prerelease) ~= "boolean" then
            table.insert(errors, "version_selection.include_prerelease must be a boolean")
        end
        if user_config.version_selection.max_versions_shown ~= nil then
            if type(user_config.version_selection.max_versions_shown) ~= "number" then
                table.insert(errors, "version_selection.max_versions_shown must be a number")
            elseif user_config.version_selection.max_versions_shown < 1 or user_config.version_selection.max_versions_shown > 100 then
                table.insert(errors, "version_selection.max_versions_shown must be between 1 and 100")
            end
        end
        if user_config.version_selection.languages then
            local valid_languages = {javascript = true, dotnet = true, go = true}
            for lang, enabled in pairs(user_config.version_selection.languages) do
                if not valid_languages[lang] then
                    table.insert(errors, string.format("Invalid language in version_selection.languages: %s", lang))
                elseif type(enabled) ~= "boolean" then
                    table.insert(errors, string.format("version_selection.languages.%s must be a boolean", lang))
                end
            end
        end
    end

    if user_config.search_batch_size ~= nil then
        if type(user_config.search_batch_size) ~= "number" then
            table.insert(errors, "search_batch_size must be a number")
        elseif user_config.search_batch_size < constants.MIN_SEARCH_BATCH_SIZE
            or user_config.search_batch_size > constants.MAX_SEARCH_BATCH_SIZE then
            table.insert(errors, string.format("search_batch_size must be between %d and %d",
                constants.MIN_SEARCH_BATCH_SIZE, constants.MAX_SEARCH_BATCH_SIZE))
        end
    end

    return errors
end

-- Public API
M.setup = function(user_config)
    user_config = user_config or {}

    local errors = validate_config(user_config)
    if #errors > 0 then
        error_handler.handle("setup", "Configuration errors:\n" .. table.concat(errors, "\n"))
        return false
    end

    config = vim.tbl_deep_extend("force", default_config, user_config)
    config.search_batch_size = constants.validate_batch_size(config.search_batch_size)

    vim.g.unipackage_config = config

    -- Clear cache on setup
    detection_cache = { cwd = nil, timestamp = nil, ttl = 5000 }

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
    return resolve_manager(false)
end

M.get_preferred_manager_silent = function()
    return resolve_manager(true)
end

M.is_manager_available = function(manager)
    return vim.tbl_contains(config.package_managers, manager)
        and vim.fn.executable(manager) == 1
end

M.get_detection_patterns = function()
    return vim.deepcopy(detection_patterns)
end

M.clear_cache = function()
    detection_cache = { cwd = nil, timestamp = nil, ttl = 5000 }
end

--- Check if version selection is enabled for a language
-- @param language string: Language name (javascript, dotnet, go)
-- @return boolean: true if version selection is enabled
function M.is_version_selection_enabled(language)
    local version_config = config.version_selection
    if not version_config or not version_config.enabled then
        return false
    end
    
    if not language then
        language = M.detect_language()
    end
    
    if not language then
        return false
    end
    
    local lang_settings = version_config.languages
    if lang_settings and lang_settings[language] ~= nil then
        return lang_settings[language]
    end
    
    return false
end

--- Get version selection configuration
-- @return table: version selection config
function M.get_version_selection_config()
    return vim.deepcopy(config.version_selection or {
        enabled = false,
        languages = {},
        include_prerelease = false,
        max_versions_shown = 20,
    })
end

return M

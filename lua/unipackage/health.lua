local M = {}

local modules = require("unipackage.core.modules")

--- Check if a command is available
-- @param cmd string: Command to check
-- @return boolean: true if available
local function check_command(cmd)
    return vim.fn.executable(cmd) == 1
end

--- Report health check result
-- @param ok boolean: Health status
-- @param message string: Message to display
local function report(ok, message)
    if ok then
        vim.health.ok(message)
    else
        vim.health.error(message)
    end
end

--- Report warning
-- @param message string: Warning message
local function warn(message)
    vim.health.warn(message)
end

--- Report info
-- @param message string: Info message
local function info(message)
    vim.health.info(message)
end

function M.check()
    vim.health.start("unipackage.nvim")

    -- Check Neovim version
    local nvim_version = vim.version()
    if nvim_version.major > 0 or (nvim_version.major == 0 and nvim_version.minor >= 7) then
        report(true, string.format("Neovim version: %d.%d.%d", nvim_version.major, nvim_version.minor, nvim_version.patch))
    else
        report(false, string.format("Neovim version %d.%d.%d is too old (requires 0.7.0+)",
            nvim_version.major, nvim_version.minor, nvim_version.patch))
    end

    -- Check required dependencies
    vim.health.start("Dependencies")

    -- Check toggleterm
    local has_toggleterm = pcall(require, "toggleterm.terminal")
    report(has_toggleterm, has_toggleterm and "toggleterm.nvim: installed" or "toggleterm.nvim: not found (required)")

    -- Check curl
    local has_curl = check_command("curl")
    report(has_curl, has_curl and "curl: available" or "curl: not found (required for search)")

    -- Check package managers
    vim.health.start("Package Managers")

    local managers = modules.get_valid_managers()
    local available_count = 0

    for _, manager in ipairs(managers) do
        local available = check_command(manager)
        if available then
            available_count = available_count + 1
            report(true, string.format("%s: available", manager))
        else
            warn(string.format("%s: not found", manager))
        end
    end

    if available_count == 0 then
        report(false, "No package managers found. Install at least one: bun, dotnet, go, npm, pnpm, or yarn")
    else
        info(string.format("Found %d/%d package managers", available_count, #managers))
    end

    -- Check current project
    vim.health.start("Project Detection")

    local config = require("unipackage.core.config")
    local detected = config.get_detected_managers()
    local language = config.detect_language()

    if language then
        report(true, string.format("Detected language: %s", language))
    else
        warn("No language detected (not in a project directory)")
    end

    if #detected > 0 then
        report(true, string.format("Detected managers: %s", table.concat(detected, ", ")))
    else
        warn("No lock files detected")
    end

    local preferred = config.get_preferred_manager_silent()
    if preferred then
        report(true, string.format("Preferred manager: %s", preferred))
    else
        warn("No preferred manager (fallback may be used)")
    end

    -- Check configuration
    vim.health.start("Configuration")

    local cfg = config.get()
    info(string.format("Search batch size: %d", cfg.search_batch_size or 20))
    info(string.format("Fallback to any: %s", cfg.fallback_to_any and "enabled" or "disabled"))
    info(string.format("Warn on fallback: %s", cfg.warn_on_fallback and "enabled" or "disabled"))

    -- Check cache
    vim.health.start("Cache")

    local cache = require("unipackage.utils.cache")
    local stats = cache.get_stats and cache.get_stats() or nil
    if stats then
        info(string.format("Cache entries: %d", stats.entries or 0))
        info(string.format("Cache size: %d bytes", stats.size or 0))
    else
        info("Cache module loaded")
    end
end

return M

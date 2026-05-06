local M = {}

local config = require("unipackage.core.config")

-- =============================================================================
-- DETECTION
-- =============================================================================

--- Check if snacks.picker is available
-- @return boolean
local function has_snacks_picker()
    local ok, _ = pcall(require, "snacks.picker")
    return ok
end

--- Check if snacks.input is available
-- @return boolean
local function has_snacks_input()
    local ok, _ = pcall(require, "snacks.input")
    return ok
end

--- Determine if we should use snacks picker
-- @return boolean
local function use_snacks()
    local picker_config = config.get("picker")
    if picker_config == "snacks" then
        return true
    elseif picker_config == "native" then
        return false
    else
        -- "auto" or default: use snacks if available
        return has_snacks_picker()
    end
end

--- Determine if we should use snacks input
-- @return boolean
local function use_snacks_input()
    local picker_config = config.get("picker")
    if picker_config == "snacks" then
        return true
    elseif picker_config == "native" then
        return false
    else
        -- "auto" or default: use snacks if available
        return has_snacks_input()
    end
end

-- =============================================================================
-- SELECT
-- =============================================================================

--- Wrapper for vim.ui.select with snacks.picker support
-- @generic T
-- @param items T[]
-- @param opts table|nil
-- @param on_choice fun(item?: T, idx?: number)
function M.select(items, opts, on_choice)
    opts = opts or {}

    if use_snacks() then
        local ok, snacks_picker = pcall(require, "snacks.picker")
        if ok and snacks_picker.select then
            -- snacks.picker.select handles format_item internally
            local success, err = pcall(snacks_picker.select, items, opts, on_choice)
            if success then
                return
            end
            -- Fall back to native on error
            vim.notify("Snacks picker failed: " .. tostring(err) .. ". Falling back to native.", vim.log.levels.WARN)
        end
    end

    -- Native fallback
    vim.ui.select(items, opts, on_choice)
end

-- =============================================================================
-- INPUT
-- =============================================================================

--- Wrapper for vim.ui.input with snacks.input support
-- @param opts table|nil
-- @param on_confirm fun(value?: string)
function M.input(opts, on_confirm)
    opts = opts or {}

    if use_snacks_input() then
        local ok, snacks_input = pcall(require, "snacks.input")
        if ok and snacks_input.input then
            local success, err = pcall(snacks_input.input, opts, on_confirm)
            if success then
                return
            end
            -- Fall back to native on error
            vim.notify("Snacks input failed: " .. tostring(err) .. ". Falling back to native.", vim.log.levels.WARN)
        end
    end

    -- Native fallback
    vim.ui.input(opts, on_confirm)
end

-- =============================================================================
-- STATUS
-- =============================================================================

--- Get current picker status information
-- @return table
function M.status()
    local picker_config = config.get("picker") or "auto"
    local snacks_available = has_snacks_picker()
    local snacks_input_available = has_snacks_input()
    local active = use_snacks()
    local input_active = use_snacks_input()

    return {
        config = picker_config,
        snacks_available = snacks_available,
        snacks_input_available = snacks_input_available,
        select_active = active,
        input_active = input_active,
    }
end

return M

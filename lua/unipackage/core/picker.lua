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

--- Check if telescope is available
-- @return boolean
local function has_telescope()
    local ok, _ = pcall(require, "telescope")
    return ok
end

--- Check if fzf-lua is available
-- @return boolean
local function has_fzf_lua()
    local ok, _ = pcall(require, "fzf-lua")
    return ok
end

-- =============================================================================
-- PICKER RESOLUTION
-- =============================================================================

--- Determine which picker to use for select
-- @return string: picker name
local function resolve_select_picker()
    local picker_config = config.get("picker")

    if picker_config == "snacks" then
        return has_snacks_picker() and "snacks" or "native"
    elseif picker_config == "telescope" then
        return has_telescope() and "telescope" or "native"
    elseif picker_config == "fzf-lua" then
        return has_fzf_lua() and "fzf-lua" or "native"
    elseif picker_config == "native" then
        return "native"
    else
        -- "auto" or default: prefer snacks, then telescope, then fzf-lua, then native
        if has_snacks_picker() then
            return "snacks"
        elseif has_telescope() then
            return "telescope"
        elseif has_fzf_lua() then
            return "fzf-lua"
        else
            return "native"
        end
    end
end

--- Determine which picker to use for input
-- @return string: picker name
local function resolve_input_picker()
    local picker_config = config.get("picker")

    if picker_config == "snacks" then
        return has_snacks_input() and "snacks" or "native"
    elseif picker_config == "native" then
        return "native"
    else
        -- "auto", "telescope", or "fzf-lua": use snacks input if available, otherwise native
        -- (telescope and fzf-lua don't have vim.ui.input replacements)
        if has_snacks_input() then
            return "snacks"
        else
            return "native"
        end
    end
end

-- =============================================================================
-- TELESCOPE SELECT
-- =============================================================================

--- Use telescope for select
-- @generic T
-- @param items T[]
-- @param opts table|nil
-- @param on_choice fun(item?: T, idx?: number)
local function telescope_select(items, opts, on_choice)
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local format_item = opts.format_item or function(item)
        return tostring(item)
    end

    -- Build formatted entries while preserving original items
    local entries = {}
    for i, item in ipairs(items) do
        table.insert(entries, {
            index = i,
            item = item,
            display = format_item(item),
        })
    end

    pickers.new(opts.telescope_opts or {}, {
        prompt_title = opts.prompt or "Select",
        finder = finders.new_table({
            results = entries,
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry.display,
                    ordinal = entry.display,
                }
            end,
        }),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection then
                    on_choice(selection.value.item, selection.value.index)
                else
                    on_choice(nil, nil)
                end
            end)
            actions.close:replace(function()
                actions.close(prompt_bufnr)
                on_choice(nil, nil)
            end)
            return true
        end,
    }):find()
end

-- =============================================================================
-- FZF-LUA SELECT
-- =============================================================================

--- Use fzf-lua for select
-- @generic T
-- @param items T[]
-- @param opts table|nil
-- @param on_choice fun(item?: T, idx?: number)
local function fzf_lua_select(items, opts, on_choice)
    local fzf_lua = require("fzf-lua")

    local format_item = opts.format_item or function(item)
        return tostring(item)
    end

    -- Build formatted entries while preserving original items
    local choices = {}
    local item_map = {}

    for i, item in ipairs(items) do
        local display = format_item(item)
        -- Use index as prefix to handle duplicate display strings
        local key = string.format("%d\t%s", i, display)
        table.insert(choices, display)
        item_map[display] = { item = item, index = i }
    end

    fzf_lua.fzf_exec(choices, {
        prompt = (opts.prompt or "Select") .. "> ",
        actions = {
            ["default"] = function(selected)
                if selected and #selected > 0 then
                    local display = selected[1]
                    local mapped = item_map[display]
                    if mapped then
                        on_choice(mapped.item, mapped.index)
                    else
                        -- Fallback: find by display text
                        for _, entry in ipairs(items) do
                            if format_item(entry) == display then
                                for j, it in ipairs(items) do
                                    if it == entry then
                                        on_choice(it, j)
                                        return
                                    end
                                end
                            end
                        end
                        on_choice(nil, nil)
                    end
                else
                    on_choice(nil, nil)
                end
            end,
        },
        fzf_opts = {
            ["--no-multi"] = "",
        },
        on_close = function()
            -- Ensure callback is called even if no selection made
            -- fzf-lua may not call actions on close, so we need to handle this
            -- We wrap the call to avoid double-calling
            local called = false
            local orig_on_choice = on_choice
            on_choice = function(item, idx)
                if not called then
                    called = true
                    orig_on_choice(item, idx)
                end
            end
        end,
    })
end

-- =============================================================================
-- SELECT
-- =============================================================================

--- Wrapper for vim.ui.select with snacks.picker, telescope, and fzf-lua support
-- @generic T
-- @param items T[]
-- @param opts table|nil
-- @param on_choice fun(item?: T, idx?: number)
function M.select(items, opts, on_choice)
    opts = opts or {}

    local picker = resolve_select_picker()

    if picker == "snacks" then
        local ok, snacks_picker = pcall(require, "snacks.picker")
        if ok and snacks_picker.select then
            local success, err = pcall(snacks_picker.select, items, opts, on_choice)
            if success then
                return
            end
            vim.notify("Snacks picker failed: " .. tostring(err) .. ". Falling back to native.", vim.log.levels.WARN)
        end
    elseif picker == "telescope" then
        local ok, _ = pcall(require, "telescope")
        if ok then
            local success, err = pcall(telescope_select, items, opts, on_choice)
            if success then
                return
            end
            vim.notify("Telescope picker failed: " .. tostring(err) .. ". Falling back to native.", vim.log.levels.WARN)
        end
    elseif picker == "fzf-lua" then
        local ok, _ = pcall(require, "fzf-lua")
        if ok then
            local success, err = pcall(fzf_lua_select, items, opts, on_choice)
            if success then
                return
            end
            vim.notify("fzf-lua picker failed: " .. tostring(err) .. ". Falling back to native.", vim.log.levels.WARN)
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

    local picker = resolve_input_picker()

    if picker == "snacks" then
        local ok, snacks_input = pcall(require, "snacks.input")
        if ok and snacks_input.input then
            local success, err = pcall(snacks_input.input, opts, on_confirm)
            if success then
                return
            end
            vim.notify("Snacks input failed: " .. tostring(err) .. ". Falling back to native.", vim.log.levels.WARN)
        end
    end

    -- Native fallback (telescope and fzf-lua don't have vim.ui.input replacements)
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
    local telescope_available = has_telescope()
    local fzf_lua_available = has_fzf_lua()
    local select_picker = resolve_select_picker()
    local input_picker = resolve_input_picker()

    return {
        config = picker_config,
        snacks_available = snacks_available,
        snacks_input_available = snacks_input_available,
        telescope_available = telescope_available,
        fzf_lua_available = fzf_lua_available,
        select_active = select_picker,
        input_active = input_picker,
    }
end

return M

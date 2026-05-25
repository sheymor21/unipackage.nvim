local M = {}

local telescope_picker = require("unipackage.core.telescope_picker")
local config = require("unipackage.core.config")

--- Check if telescope support is enabled in config
local function telescope_enabled()
	local ui_config = config.get("ui")
	return ui_config and ui_config.telescope == true
end

-- =============================================================================
-- STATUS
-- =============================================================================

--- Get picker status for health checks
-- @return table: { dressing_available = boolean, telescope_enabled = boolean, telescope_available = boolean }
function M.status()
	local has_dressing = pcall(require, "dressing")
	return {
		dressing_available = has_dressing,
		telescope_enabled = telescope_enabled(),
		telescope_available = telescope_picker.is_available(),
	}
end

-- =============================================================================
-- SELECT
-- =============================================================================

--- Wrapper for vim.ui.select with optional telescope enhancement
-- @generic T
-- @param items T[]
-- @param opts table|nil
-- @param on_choice fun(item?: T, idx?: number)
function M.select(items, opts, on_choice)
	if telescope_enabled() then
		local ok = telescope_picker.select(items, opts, on_choice)
		if ok then
			return
		end
	end
	vim.ui.select(items, opts or {}, on_choice)
end

-- =============================================================================
-- INPUT
-- =============================================================================

--- Wrapper for vim.ui.input
-- @param opts table|nil
-- @param on_confirm fun(value?: string)
function M.input(opts, on_confirm)
	vim.ui.input(opts or {}, on_confirm)
end

-- =============================================================================
-- PACKAGE MENU (Telescope enhanced)
-- =============================================================================

--- Show package menu with enhanced telescope UI when available
-- @param items table[]: Array of { text, icon, func, value }
-- @param opts table: Options { manager, detected }
-- @param on_select fun(item): Callback when an item is selected
function M.package_menu(items, opts, on_select)
	if telescope_enabled() then
		local ok = telescope_picker.package_menu(items, opts, on_select)
		if ok then
			return
		end
	end
	-- Fallback to vim.ui.select
	local option_names = {}
	for _, item in ipairs(items) do
		table.insert(option_names, item.text or item)
	end

	local manager = opts.manager or ""
	local prompt = opts.prompt or (manager ~= "" and "Package Management [" .. manager:upper() .. "]" or "Package Management")

	vim.ui.select(option_names, {
		prompt = prompt,
	}, function(choice, idx)
		if choice and idx and on_select then
			on_select(items[idx])
		end
	end)
end

return M

local M = {}

local has_telescope, telescope = pcall(require, "telescope")
local has_tpickers, pickers = pcall(require, "telescope.pickers")
local has_tfinders, finders = pcall(require, "telescope.finders")
local has_tconf, conf = pcall(require, "telescope.config")
local has_tactions, actions = pcall(require, "telescope.actions")
local has_taction_state, action_state = pcall(require, "telescope.actions.state")
local has_tthemes, themes = pcall(require, "telescope.themes")

local icons = require("unipackage.core.icons")

-- =============================================================================
-- TELESCOPE AVAILABILITY
-- =============================================================================

function M.is_available()
	return has_telescope
		and has_tpickers
		and has_tfinders
		and has_tconf
		and has_tactions
		and has_taction_state
end

-- =============================================================================
-- HIGHLIGHTS
-- =============================================================================

local function setup_highlights()
	local hl_groups = {
		UniPackageManager = { link = "Special" },
		UniPackageSelected = { link = "Keyword" },
		UniPackageArrow = { link = "DiagnosticInfo" },
	}

	for name, def in pairs(hl_groups) do
		local ok, _ = pcall(vim.api.nvim_get_hl, 0, { name = name })
		if not ok then
			pcall(vim.api.nvim_set_hl, 0, name, def)
		end
	end
end

-- =============================================================================
-- DISPLAY UTILITIES
-- =============================================================================

local function create_entry_display(show_manager, manager_width)
	local ok, entry_display = pcall(require, "telescope.pickers.entry_display")
	if not ok then
		return nil
	end

	local items = {
		{ width = 2 },      -- icon
		{ remaining = true }, -- text (fills remaining space)
	}

	if show_manager then
		table.insert(items, { width = manager_width or 4 })
	end

	return entry_display.create({
		separator = " ",
		items = items,
	})
end

local function format_menu_item(display, item, manager)
	local icon = item.icon or ""
	local text = item.text or ""

	if display then
		if manager and manager ~= "" then
			return display({
				{ icon, "Normal" },
				{ text, "Normal" },
				{ manager:upper(), "UniPackageManager" },
			})
		else
			return display({
				{ icon, "Normal" },
				{ text, "Normal" },
			})
		end
	end

	if manager and manager ~= "" then
		return string.format("%s %s %s", icon, text, manager:upper())
	else
		return string.format("%s %s", icon, text)
	end
end

-- =============================================================================
-- PACKAGE MENU PICKER
-- =============================================================================

--- Show a custom Telescope picker for the package menu
-- @param items table[]: Array of { text, icon, func, value }
-- @param opts table: Options { manager, detected }
-- @param on_select fun(item): Callback when an item is selected
function M.package_menu(items, opts, on_select)
	if not M.is_available() then
		return false
	end

	setup_highlights()

	opts = opts or {}
	local manager = opts.manager or ""
	local manager_upper = manager:upper()

	local picker_opts = themes.get_dropdown({
		prompt_title = icons.prompt("package", "Package Management") .. (manager_upper ~= "" and " [" .. manager_upper .. "]" or ""),
		results_title = false,
		prompt_prefix = "  ",
		selection_caret = icons.get("arrow", "›") .. " ",
		entry_prefix = "  ",
		layout_config = {
			width = 0.3,
			height = math.min(10, #items + 4),
		},
		borderchars = {
			prompt = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
			results = { "─", "│", "─", "│", "├", "┤", "╯", "╰" },
			preview = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
		},
	})

	local display = create_entry_display(false)

	local finder = finders.new_table({
		results = items,
		entry_maker = (function()
			local idx = 0
			return function(item)
				idx = idx + 1
				local num_text = string.format("%d. %s", idx, item.text or "")
				local num_ordinal = string.format("%d %s", idx, item.text or "")
				local display_item = vim.tbl_extend("force", item, { text = num_text })
				return {
					value = item,
					display = function()
						return format_menu_item(display, display_item)
					end,
					ordinal = num_ordinal,
				}
			end
		end)(),
	})

	local picker = pickers.new(picker_opts, {
		finder = finder,
		sorter = conf.values.generic_sorter(picker_opts),
		attach_mappings = function(bufnr, map)
			actions.select_default:replace(function()
				local entry = action_state.get_selected_entry()
				actions.close(bufnr)
				if entry and on_select then
					on_select(entry.value)
				end
			end)
			return true
		end,
	})

	picker:find()
	return true
end

-- =============================================================================
-- SELECT FALLBACK
-- =============================================================================

--- Enhanced select with telescope when available
-- @param items table[]: Array of items
-- @param opts table: Options { prompt, format_item }
-- @param on_choice fun(item, idx): Callback
function M.select(items, opts, on_choice)
	if not M.is_available() then
		return false
	end

	opts = opts or {}

	local picker_opts = themes.get_dropdown({
		prompt_title = opts.prompt or "Select",
		results_title = false,
		prompt_prefix = "  ",
		selection_caret = icons.get("arrow", "›") .. " ",
		entry_prefix = "  ",
		layout_config = {
			width = 0.3,
			height = math.min(10, #items + 3),
		},
		borderchars = {
			prompt = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
			results = { "─", "│", "─", "│", "├", "┤", "╯", "╰" },
			preview = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
		},
	})

	local finder = finders.new_table({
		results = items,
		entry_maker = function(item)
			local text = opts.format_item and opts.format_item(item) or tostring(item)
			return {
				value = item,
				display = text,
				ordinal = text,
			}
		end,
	})

	local picker = pickers.new(picker_opts, {
		finder = finder,
		sorter = conf.values.generic_sorter(picker_opts),
		attach_mappings = function(bufnr, map)
			actions.select_default:replace(function()
				local entry = action_state.get_selected_entry()
				actions.close(bufnr)
				if entry and on_choice then
					on_choice(entry.value, entry.index)
				end
			end)
			return true
		end,
	})

	picker:find()
	return true
end

-- =============================================================================
-- INPUT FALLBACK
-- =============================================================================

function M.input(opts, on_confirm)
	-- Telescope doesn't have a built-in input picker, use vim.ui.input
	return false
end

return M

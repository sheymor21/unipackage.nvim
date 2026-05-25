local M = {}

-- =============================================================================
-- ICON SETS
-- =============================================================================

local nerd = {
	install = "󰐖",
	uninstall = "󰆴",
	list = "󰋱",
	search = "󰍉",
	info = "󰋽",
	refresh = "󰑓",
	arrow = "󰜴",
	yes = "󰄬",
	no = "󰅖",
	back = "󰜵",
	package = "󰏗",
	loading = "󰔛",
	success = "󰄬",
	warning = "󰀦",
	question = "󰋗",
	dotnet = "󰌛",
	go = "󰟓",
	node = "󰎙",
	project = "󰉋",
	reference = "󰌷",
	tidy = "󰃢",
	version = "󰕗",
	batch = "󰏗",
	bullet = "•",
	star = "★",
	check = "✓",
	folder = "󰉋",
	count = "󰘔",
}

local plain = {
	install = "⊕",
	uninstall = "⊖",
	list = "≡",
	search = "⊙",
	info = "◉",
	refresh = "↻",
	arrow = "▸",
	yes = "✓",
	no = "✗",
	back = "◂",
	package = "◆",
	loading = "◐",
	success = "✓",
	warning = "▲",
	question = "◈",
	dotnet = "◆",
	go = "◎",
	node = "●",
	project = "▸",
	reference = "∞",
	tidy = "✧",
	version = "⌘",
	batch = "⋯",
	bullet = "•",
	star = "★",
	check = "✓",
	folder = "▸",
	count = "#",
}

local active = vim.deepcopy(nerd)

-- =============================================================================
-- DETECTION
-- =============================================================================

local function detect_nerd_font()
	local ok, width = pcall(vim.fn.strdisplaywidth, nerd.install)
	if not ok then return false end
	return width == 1
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

function M.get(name, fallback)
	return active[name] or fallback or ""
end

function M.set(preset)
	if preset == "plain" then
		active = vim.deepcopy(plain)
	elseif preset == "nerd" then
		active = vim.deepcopy(nerd)
	elseif preset == "auto" then
		if detect_nerd_font() then
			active = vim.deepcopy(nerd)
		else
			active = vim.deepcopy(plain)
		end
	elseif type(preset) == "table" then
		active = vim.tbl_extend("force", vim.deepcopy(nerd), preset)
	else
		active = detect_nerd_font() and vim.deepcopy(nerd) or vim.deepcopy(plain)
	end
end

function M.format(name, text)
	local icon = M.get(name, "")
	if icon == "" then return text end
	return icon .. "  " .. text
end

function M.prompt(name, text)
	local icon = M.get(name, "")
	if icon == "" then return text end
	return icon .. " " .. text
end

-- Auto-detect on module load
M.set("auto")

return M

local M = {}

local error_handler = require("unipackage.core.error")

-- Default terminal appearance configuration
local default_appearance = {
    -- Float window options
    float_opts = {
        border = "single",
        width = function()
            return math.floor(vim.o.columns * 0.8)
        end,
        height = function()
            return math.floor(vim.o.lines * 0.8)
        end,
        winblend = 0,
        zindex = 50,
    },
    -- Visual highlights with theme colors
    highlights = {
        Normal = {
            guibg = nil,
        },
        NormalFloat = {
            guibg = nil,
        },
        FloatBorder = {
            guifg = "#7aa2f7",
            guibg = nil,
        },
    },
    -- Display options
    display = {
        show_title = true,
        title_prefix = " ",
        title_suffix = " ",
        show_header = true,
        show_package_count = true,
    },
    -- Theme colors (Tokyo Night inspired)
    colors = {
        primary = "#7aa2f7",
        secondary = "#bb9af7",
        success = "#9ece6a",
        warning = "#e0af68",
        error = "#f7768e",
        info = "#565f89",
        muted = "#565f89",
    },
}

-- Terminal-style icons
local icons = {
    package = "[*]",
    folder = "[>]",
    count = "[#]",
    version = "[v]",
    arrow = "->",
    bullet = "*",
    star = "*",
    check = "[OK]",
    info = "[i]",
}

--- Apply highlight configurations
local function apply_highlights()
    for group, colors in pairs(default_appearance.highlights) do
        local highlight_cmd = "silent! highlight " .. group
        if colors.guifg then
            highlight_cmd = highlight_cmd .. " guifg=" .. colors.guifg
        end
        if colors.guibg then
            highlight_cmd = highlight_cmd .. " guibg=" .. colors.guibg
        end
        if colors.gui then
            highlight_cmd = highlight_cmd .. " gui=" .. colors.gui
        end
        vim.cmd(highlight_cmd)
    end
end

--- Get theme color
-- @param color_name string: Color name (primary, secondary, success, warning, error, info, muted)
-- @return string: Hex color code
function M.get_color(color_name)
    return default_appearance.colors[color_name] or default_appearance.colors.info
end

--- Format text with ANSI color codes
-- @param text string: Text to format
-- @param color string: Color name
-- @param bold boolean|nil: Whether to make text bold
-- @return string: Formatted text with ANSI codes
function M.colorize(text, color, bold)
    local color_map = {
        primary = "34",   -- Blue
        secondary = "35", -- Magenta
        success = "32",   -- Green
        warning = "33",   -- Yellow
        error = "31",     -- Red
        info = "36",      -- Cyan
        muted = "90",     -- Bright black
    }

    local code = color_map[color] or "0"
    if bold then
        code = "1;" .. code
    end

    return string.format("\27[%sm%s\27[0m", code, text)
end

--- Build styled header for terminal output with terminal-style icons
-- @param manager string: Package manager name
-- @param info table|nil: Additional info {project_path, package_count, version}
-- @return string: Styled header text
function M.build_header(manager, info)
    if not default_appearance.display.show_header then
        return ""
    end

    info = info or {}
    local lines = {}
    local width = 70

    -- Helper to create a line with borders
    local function make_line(content, icon)
        local prefix = icon and (icon .. " ") or ""
        local full_content = prefix .. content
        local padding = width - #full_content - 4
        if padding < 0 then padding = 0 end
        return "| " .. full_content .. string.rep(" ", padding) .. " |"
    end

    -- Top border
    table.insert(lines, "")
    table.insert(lines, M.colorize("+" .. string.rep("-", width - 2) .. "+", "info"))

    -- Manager name with icon
    local manager_text = manager:upper() .. " Package Manager"
    table.insert(lines, M.colorize(make_line(manager_text, icons.package), "warning"))

    -- Separator
    table.insert(lines, M.colorize("|" .. string.rep("-", width - 2) .. "|", "info"))

    -- Project path
    if info.project_path then
        table.insert(lines, M.colorize(make_line(info.project_path, icons.folder), "muted"))
    end

    -- Package count
    if info.package_count and default_appearance.display.show_package_count then
        local count_text = "Packages: " .. tostring(info.package_count)
        table.insert(lines, M.colorize(make_line(count_text, icons.count), "success"))
    end

    -- Version info
    if info.version then
        local version_text = "Version: " .. info.version
        table.insert(lines, M.colorize(make_line(version_text, icons.version), "info"))
    end

    -- Bottom border
    table.insert(lines, M.colorize("+" .. string.rep("-", width - 2) .. "+", "info"))
    table.insert(lines, "")

    return table.concat(lines, "\n")
end

--- Build float options with proper sizing
-- @param opts table|nil: User provided options
-- @return table: Complete float options
local function build_float_opts(opts)
    opts = opts or {}
    local float_opts = vim.deepcopy(default_appearance.float_opts)

    -- Override with user options
    if opts.border then
        float_opts.border = opts.border
    end
    if opts.width then
        float_opts.width = opts.width
    end
    if opts.height then
        float_opts.height = opts.height
    end
    if opts.winblend ~= nil then
        float_opts.winblend = opts.winblend
    end

    -- Calculate dimensions if functions
    if type(float_opts.width) == "function" then
        float_opts.width = float_opts.width()
    end
    if type(float_opts.height) == "function" then
        float_opts.height = float_opts.height()
    end

    return float_opts
end

--- Build terminal title
-- @param cmd string: Command being executed
-- @param opts table|nil: Options with title info
-- @return string|nil: Formatted title or nil
local function build_title(cmd, opts)
    if not default_appearance.display.show_title then
        return nil
    end

    local title = opts.title
    if not title and cmd then
        -- Extract package manager from command
        local manager = cmd:match("^(%S+)")
        if manager then
            title = manager:upper()
        end
    end

    if title then
        return default_appearance.display.title_prefix .. title .. default_appearance.display.title_suffix
    end
    return nil
end

--- Create and run a terminal command using ToggleTerm
-- @param cmd string: Command to execute
-- @param opts table|nil: Options {direction, close_on_exit, hidden, title, border, width, height}
-- @return boolean: success status
function M.run(cmd, opts)
    opts = opts or {}
    local direction = opts.direction or "float"
    local close_on_exit = opts.close_on_exit
    if close_on_exit == nil then
        close_on_exit = false
    end
    local hidden = opts.hidden
    if hidden == nil then
        hidden = true
    end

    local ok, Terminal = pcall(require, "toggleterm.terminal")
    if not ok then
        error_handler.handle("terminal", "toggleterm.nvim is required but not installed")
        return false
    end

    -- Apply highlights for better appearance
    apply_highlights()

    -- Build terminal options
    local terminal_opts = {
        direction = direction,
        close_on_exit = close_on_exit,
        hidden = hidden,
    }

    -- Add float options for floating terminals
    if direction == "float" then
        terminal_opts.float_opts = build_float_opts(opts)
        terminal_opts.on_open = function(term)
            -- Center the terminal
            local width = terminal_opts.float_opts.width
            local height = terminal_opts.float_opts.height
            local col = math.floor((vim.o.columns - width) / 2)
            local row = math.floor((vim.o.lines - height) / 2)

            vim.api.nvim_win_set_config(term.window, {
                relative = "editor",
                row = row,
                col = col,
                width = width,
                height = height,
                border = terminal_opts.float_opts.border,
                zindex = terminal_opts.float_opts.zindex,
            })
        end
    end

    -- Add title if specified
    local title = build_title(cmd, opts)
    if title then
        terminal_opts.display_name = title
    end

    local runner = Terminal.Terminal:new(terminal_opts)
    runner.cmd = cmd

    local toggle_ok, err = pcall(runner.toggle, runner)
    if not toggle_ok then
        error_handler.handle("terminal", "Failed to execute: " .. tostring(err))
        return false
    end

    return true
end

--- Create a terminal runner without executing
-- @param cmd string: Command to execute
-- @param opts table|nil: Options {direction, close_on_exit, hidden, title, border, width, height}
-- @return table|nil: Terminal runner or nil on error
function M.create(cmd, opts)
    opts = opts or {}

    local ok, Terminal = pcall(require, "toggleterm.terminal")
    if not ok then
        error_handler.handle("terminal", "toggleterm.nvim is required but not installed")
        return nil
    end

    -- Apply highlights for better appearance
    apply_highlights()

    -- Build terminal options
    local terminal_opts = {
        direction = opts.direction or "float",
        close_on_exit = opts.close_on_exit or false,
        hidden = opts.hidden or true,
    }

    -- Add float options for floating terminals
    if terminal_opts.direction == "float" then
        terminal_opts.float_opts = build_float_opts(opts)
        terminal_opts.on_open = function(term)
            local width = terminal_opts.float_opts.width
            local height = terminal_opts.float_opts.height
            local col = math.floor((vim.o.columns - width) / 2)
            local row = math.floor((vim.o.lines - height) / 2)

            vim.api.nvim_win_set_config(term.window, {
                relative = "editor",
                row = row,
                col = col,
                width = width,
                height = height,
                border = terminal_opts.float_opts.border,
                zindex = terminal_opts.float_opts.zindex,
            })
        end
    end

    -- Add title if specified
    local title = build_title(cmd, opts)
    if title then
        terminal_opts.display_name = title
    end

    local runner = Terminal.Terminal:new(terminal_opts)
    runner.cmd = cmd
    return runner
end

--- Run a command with styled header and output
-- @param cmd string: Command to execute
-- @param opts table|nil: Options {manager, project_path, package_count, version, title}
-- @return boolean: success status
function M.run_with_header(cmd, opts)
    opts = opts or {}
    local manager = opts.manager or "Package Manager"

    -- Build the header
    local header = M.build_header(manager, {
        project_path = opts.project_path or vim.fn.getcwd(),
        package_count = opts.package_count,
        version = opts.version,
    })

    -- Create a wrapper command that prints header then runs the actual command
    local wrapper_cmd
    if header ~= "" then
        wrapper_cmd = string.format('echo "%s" && %s', header:gsub('"', '\\"'), cmd)
    else
        wrapper_cmd = cmd
    end

    return M.run(wrapper_cmd, {
        title = opts.title or manager,
    })
end

--- Run a list command with package count
-- @param cmd string: The list command
-- @param manager string: Package manager name
-- @param opts table|nil: Additional options
function M.run_list(cmd, manager, opts)
    opts = opts or {}

    -- Get package count from the module
    local modules = require("unipackage.core.modules")
    local module = modules.load(manager)
    local package_count = nil

    if module and module.get_installed_packages then
        local packages = module.get_installed_packages()
        package_count = #packages
    end

    -- Get manager version
    local version = nil
    local version_cmd = manager .. " --version 2>/dev/null || " .. manager .. " -v 2>/dev/null"
    local handle = io.popen(version_cmd)
    if handle then
        version = handle:read("*l")
        handle:close()
        if version then
            version = version:gsub("^%s*", ""):gsub("%s*$", "")
        end
    end

    return M.run_with_header(cmd, {
        manager = manager,
        project_path = vim.fn.getcwd(),
        package_count = package_count,
        version = version,
        title = manager .. " List",
    })
end

--- Get default appearance configuration
-- @return table: Current appearance settings
function M.get_appearance()
    return vim.deepcopy(default_appearance)
end

--- Update appearance configuration
-- @param opts table: Appearance options to override
function M.set_appearance(opts)
    if opts.float_opts then
        default_appearance.float_opts = vim.tbl_deep_extend("force", default_appearance.float_opts, opts.float_opts)
    end
    if opts.highlights then
        default_appearance.highlights = vim.tbl_deep_extend("force", default_appearance.highlights, opts.highlights)
    end
    if opts.display then
        default_appearance.display = vim.tbl_deep_extend("force", default_appearance.display, opts.display)
    end
    if opts.colors then
        default_appearance.colors = vim.tbl_deep_extend("force", default_appearance.colors, opts.colors)
    end
end

return M

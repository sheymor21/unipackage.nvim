local M = {}

local error_handler = require("unipackage.core.error")

--- Create and run a terminal command using ToggleTerm
-- @param cmd string: Command to execute
-- @param opts table|nil: Options {direction, close_on_exit, hidden}
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

    local runner = Terminal.Terminal:new({
        direction = direction,
        close_on_exit = close_on_exit,
        hidden = hidden,
    })

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
-- @param opts table|nil: Options
-- @return table|nil: Terminal runner or nil on error
function M.create(cmd, opts)
    opts = opts or {}

    local ok, Terminal = pcall(require, "toggleterm.terminal")
    if not ok then
        error_handler.handle("terminal", "toggleterm.nvim is required but not installed")
        return nil
    end

    local runner = Terminal.Terminal:new({
        direction = opts.direction or "float",
        close_on_exit = opts.close_on_exit or false,
        hidden = opts.hidden or true,
    })

    runner.cmd = cmd
    return runner
end

return M

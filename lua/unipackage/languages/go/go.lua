local M = {}

local terminal = require("unipackage.core.terminal")

-- Minimum Go version required (1.18+ for workspace support)
local MIN_GO_VERSION = "1.18"

--- Check if Go version meets minimum requirement
-- @return boolean: true if Go is available and version is sufficient
local function check_go_version()
    local handle = io.popen("go version 2>/dev/null")
    if not handle then
        return false
    end
    
    local output = handle:read("*a")
    handle:close()
    
    -- Parse version from "go version go1.18.3 linux/amd64"
    local version = output:match("go(%d+%.%d+)")
    if not version then
        return false
    end
    
    -- Simple version comparison
    local function parse_version(v)
        local major, minor = v:match("(%d+)%.(%d+)")
        return tonumber(major) * 100 + tonumber(minor)
    end
    
    return parse_version(version) >= parse_version(MIN_GO_VERSION)
end

--- Check if current directory is a Go workspace
-- @return boolean: true if go.work exists
function M.is_workspace()
    local cwd = vim.fn.getcwd()
    local work_file = cwd .. "/go.work"
    local stat = vim.uv.fs_stat(work_file)
    return stat ~= nil
end

--- Get workspace modules from go.work
-- @return table: list of module paths in workspace
function M.get_workspace_modules()
    if not M.is_workspace() then
        return {}
    end
    
    local handle = io.popen("go work edit -json 2>/dev/null")
    if not handle then
        return {}
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local ok, work_json = pcall(vim.fn.json_decode, output)
    if not ok or not work_json or not work_json.Use then
        return {}
    end
    
    local modules = {}
    for _, mod in ipairs(work_json.Use) do
        if mod.DiskPath then
            table.insert(modules, mod.DiskPath)
        end
    end
    
    return modules
end

--- Execute Go command via ToggleTerm
-- @param args table: command arguments
function M.run_command(args)
    if not check_go_version() then
        vim.notify("Go " .. MIN_GO_VERSION .. "+ is required for workspace support", vim.log.levels.ERROR)
        return
    end

    args = args or {}

    local cmd
    if args[1] == "install" then
        -- Transform install to go get
        local packages = {}
        for i = 2, #args do
            table.insert(packages, args[i])
        end
        cmd = "go get " .. table.concat(packages, " ")
    elseif args[1] == "list" then
        cmd = "go list -m all"
    elseif args[1] == "tidy" then
        cmd = "go mod tidy"
        terminal.run_with_header(cmd, {
            manager = "Go",
            title = "Go Mod Tidy",
        })
        return
    else
        -- Direct go command
        cmd = "go " .. table.concat(args, " ")
    end

    terminal.run(cmd, { title = "Go" })
end

--- Gets installed packages from go list output
-- @return table: list of installed package names
function M.get_installed_packages()
    local cmd
    if M.is_workspace() then
        -- For workspaces, list all modules
        cmd = "go list -m all 2>/dev/null"
    else
        cmd = "go list -m all 2>/dev/null"
    end
    
    local handle = io.popen(cmd)
    if not handle then
        return {}
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local packages = {}
    for line in output:gmatch("[^\r\n]+") do
        -- Skip empty lines and the main module line
        if line ~= "" and not line:match("^%s*$") then
            -- Parse "module version" format
            local mod = line:match("^([^%s]+)")
            if mod and mod ~= "" then
                table.insert(packages, mod)
            end
        end
    end
    
    return packages
end

return M

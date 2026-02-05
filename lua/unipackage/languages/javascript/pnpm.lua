local M = {}

--- Executes pnpm commands in the current directory using ToggleTerm
-- @param args table: arguments for pnpm command, e.g., {"install"} or {"remove", "package"}
function M.run_command(args)
    args = args or {}

    local Terminal = require("toggleterm.terminal").Terminal

    local runner = Terminal:new({
        direction = "float",
        close_on_exit = false,
        hidden = true,
    })

    -- Build command: "pnpm " .. table.concat(args, " ")
    local cmd = "pnpm " .. table.concat(args, " ")

    runner.cmd = cmd
    runner:toggle()
end

--- Gets installed packages from pnpm list output
-- @return table: list of installed package names
function M.get_installed_packages()
    local handle = io.popen("pnpm list --depth=0 2>/dev/null")
    if not handle then
        return {}
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local packages = {}
    for line in output:gmatch("[^\r\n]+") do
        -- Skip empty lines and pnpm list header
        if line ~= "" and not line:match("^pnpm list") then
            -- Match pnpm list format: simpler than npm/yarn trees
            -- Format: "package@version" or with tree symbols
            local package = line:match("│? *├──? *([^@%s]+)@[^%s]+")
            if not package then
                package = line:match("│? *└──? *([^@%s]+)@[^%s]+")
            end
            if not package then
                -- Fallback: match package@version directly
                package = line:match("([^@%s]+)@[^%s]+$") 
            end
            
            if package and package ~= "" and package:lower() ~= "pnpm" then
                -- Clean up package name
                package = package:gsub("^%s+", ""):gsub("%s+$", "")
                if package ~= "" then
                    table.insert(packages, package)
                end
            end
        end
    end
    
    return packages
end

--- Checks if current project uses pnpm workspaces
-- @return boolean: true if pnpm-workspace.yaml exists
function M.is_workspace()
    local workspace_file = vim.fn.getcwd() .. "/pnpm-workspace.yaml"
    return vim.fn.filereadable(workspace_file) == 1
end

return M

local M = {}

--- Executes npm commands in the current directory using ToggleTerm
-- @param args table: arguments for npm command, e.g., {"install"} or {"uninstall", "package"}
function M.run_command(args)
    args = args or {}

    local Terminal = require("toggleterm.terminal").Terminal

    local runner = Terminal:new({
        direction = "float",
        close_on_exit = false,
        hidden = true,
    })

    -- Build command: "npm " .. table.concat(args, " ")
    local cmd = "npm " .. table.concat(args, " ")

    runner.cmd = cmd
    runner:toggle()
end

--- Gets installed packages from npm list output
-- @return table: list of installed package names
function M.get_installed_packages()
    local handle = io.popen("npm list --depth=0 2>/dev/null")
    if not handle then
        return {}
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local packages = {}
    for line in output:gmatch("[^\r\n]+") do
        -- Skip empty lines and project header
        if line ~= "" and not line:match("^%w+@") then
            -- Match npm list format variations
            local package = line:match("│? *├──? *([^@%s]+)@[^%s]+")
            if not package then
                package = line:match("│? *└──? *([^@%s]+)@[^%s]+")
            end
            if not package then
                -- Fallback: match package@version anywhere in line
                package = line:match("([^@%s]+)@[^%s]+$") 
            end
            
            if package and package ~= "" and package:lower() ~= "npm" then
                -- Clean up package name
                package = package:gsub("[%s│└├─]", "")
                if package ~= "" then
                    table.insert(packages, package)
                end
            end
        end
    end
    
    return packages
end

return M

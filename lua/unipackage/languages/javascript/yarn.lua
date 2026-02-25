local M = {}

local terminal = require("unipackage.core.terminal")

--- Executes yarn commands in the current directory using ToggleTerm
-- @param args table: arguments for yarn command, e.g., {"install"} or {"remove", "package"}
function M.run_command(args)
    args = args or {}

    local cmd = "yarn " .. table.concat(args, " ")
    terminal.run(cmd, { title = "Yarn" })
end

--- Gets installed packages from yarn list output
-- @return table: list of installed package names
function M.get_installed_packages()
    local handle = io.popen("yarn list --depth=0 2>/dev/null")
    if not handle then
        return {}
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local packages = {}
    for line in output:gmatch("[^\r\n]+") do
        -- Skip empty lines and yarn list header
        if line ~= "" and not line:match("^yarn list v") then
            -- Match yarn list format variations: "├─ package@version" or "└─ package@version"
            local package = line:match("[├└]─? *([^@%s]+)@[^%s]+")
            if not package then
                -- Fallback: match package@version anywhere in line
                package = line:match("([^@%s]+)@[^%s]+$") 
            end
            
            if package and package ~= "" and package:lower() ~= "yarn" then
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

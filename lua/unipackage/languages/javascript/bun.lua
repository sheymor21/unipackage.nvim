local M = {}

local terminal = require("unipackage.core.terminal")

--- Ejecuta un comando de Bun en el directorio actual usando ToggleTerm
-- @param args table: argumentos del comando Bun, ejemplo {"install"} o {"run", "dev"}
function M.run_command(args)
    args = args or {}

    local cmd = "bun " .. table.concat(args, " ")
    terminal.run(cmd, { title = "Bun" })
end

--- Gets installed packages from bun list output
-- @return table: list of installed package names
function M.get_installed_packages()
    local handle = io.popen("bun list 2>/dev/null")
    if not handle then
        return {}
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local packages = {}
    for line in output:gmatch("[^\r\n]+") do
        -- Match package lines like "├── package@version" or "└── package@version"
        local package = line:match("([^%s]+)@[^%s]+$")
        if package then
            package = package:gsub("%s+", "") -- Remove any whitespace
            table.insert(packages, package)
        end
    end
    
    return packages
end

return M

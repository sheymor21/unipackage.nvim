local M = {}

--- Check if current directory has a solution file
-- @return string|nil: solution filename or nil
function M.get_solution_file()
    local cwd = vim.fn.getcwd()
    local handle = io.popen("ls *.sln 2>/dev/null")
    if not handle then
        return nil
    end
    
    local output = handle:read("*a")
    handle:close()
    
    -- Return first .sln file found
    for line in output:gmatch("[^\r\n]+") do
        if line:match("%.sln$") then
            return line
        end
    end
    
    return nil
end

--- Check if working at solution level
-- @return boolean: true if .sln file exists
function M.is_solution_level()
    return M.get_solution_file() ~= nil
end

--- Execute dotnet command via ToggleTerm
-- @param args table: command arguments
function M.run_command(args)
    args = args or {}
    
    local Terminal = require("toggleterm.terminal").Terminal
    local runner = Terminal:new({
        direction = "float",
        close_on_exit = false,
        hidden = true,
    })
    
    local cmd
    if args[1] == "install" then
        -- dotnet add package <name>
        local packages = {}
        for i = 2, #args do
            table.insert(packages, args[i])
        end
        if #packages == 0 then
            vim.notify("No package specified for installation", vim.log.levels.ERROR)
            return
        end
        -- For solution level, we might need to specify a project
        -- For now, let dotnet handle it
        cmd = "dotnet add package " .. packages[1]
    elseif args[1] == "remove" then
        -- dotnet remove package <name>
        local package = args[2]
        if not package then
            vim.notify("No package specified for removal", vim.log.levels.ERROR)
            return
        end
        
        -- Show confirmation dialog
        vim.ui.select({"Yes", "No"}, {
            prompt = "Remove package: " .. package .. "?",
        }, function(choice)
            if choice == "Yes" then
                runner.cmd = "dotnet remove package " .. package
                runner:toggle()
                vim.notify("Package '" .. package .. "' removed", vim.log.levels.INFO)
            end
        end)
        return
    elseif args[1] == "list" then
        cmd = "dotnet list package"
    elseif args[1] == "restore" then
        cmd = "dotnet restore"
    elseif args[1] == "reference" then
        -- dotnet add reference <project>
        local project = args[2]
        if not project then
            vim.notify("No project specified for reference", vim.log.levels.ERROR)
            return
        end
        cmd = "dotnet add reference " .. project
    else
        -- Direct dotnet command
        cmd = "dotnet " .. table.concat(args, " ")
    end
    
    runner.cmd = cmd
    runner:toggle()
end

--- Gets installed packages from dotnet list output
-- @return table: list of installed package names
function M.get_installed_packages()
    local handle = io.popen("dotnet list package --format json 2>/dev/null")
    if not handle then
        return {}
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local packages = {}
    
    -- Try to parse JSON output
    local ok, json_data = pcall(vim.fn.json_decode, output)
    if ok and json_data and json_data.projects then
        for _, project in ipairs(json_data.projects) do
            if project.frameworks then
                for _, framework in ipairs(project.frameworks) do
                    if framework.topLevelPackages then
                        for _, pkg in ipairs(framework.topLevelPackages) do
                            if pkg.id then
                                table.insert(packages, pkg.id)
                            end
                        end
                    end
                end
            end
        end
    else
        -- Fallback: parse text output
        handle = io.popen("dotnet list package 2>/dev/null")
        if handle then
            output = handle:read("*a")
            handle:close()
            
            for line in output:gmatch("[^\r\n]+") do
                -- Match package lines like "> package-name version"
                local pkg = line:match(">%s+([^%s]+)")
                if pkg and not pkg:match("^Package") then
                    table.insert(packages, pkg)
                end
            end
        end
    end
    
    return packages
end

--- Get list of projects in solution or directory
-- @return table: list of project files
function M.get_projects()
    local projects = {}
    
    -- Try to get projects from solution
    local handle = io.popen("dotnet sln list 2>/dev/null")
    if handle then
        local output = handle:read("*a")
        handle:close()
        
        for line in output:gmatch("[^\r\n]+") do
            -- Skip header lines and empty lines
            if not line:match("^Project%(s%)" ) and not line:match("^%-+$") and line ~= "" then
                if line:match("%.csproj$") or line:match("%.fsproj$") or line:match("%.vbproj$") then
                    table.insert(projects, line)
                end
            end
        end
    end
    
    -- If no projects found in solution, search for project files
    if #projects == 0 then
        handle = io.popen("find . -maxdepth 2 -name '*.csproj' -o -name '*.fsproj' -o -name '*.vbproj' 2>/dev/null")
        if handle then
            local output = handle:read("*a")
            handle:close()
            
            for line in output:gmatch("[^\r\n]+") do
                -- Remove leading ./
                line = line:gsub("^%./", "")
                table.insert(projects, line)
            end
        end
    end
    
    return projects
end

return M

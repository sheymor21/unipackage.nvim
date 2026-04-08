local M = {}

local xml2lua = nil
local handler = nil

-- Try to load xml2lua if available
local function try_load_xml2lua()
    if xml2lua then return true end
    local ok, mod = pcall(require, "xml2lua")
    if ok then
        xml2lua = mod
        handler = require("xml2lua.xmlhandler.tree")
        return true
    end
    return false
end

-- Parse credentials from nuget.config manually
local function parse_credentials_manual(content)
    local credentials = {}
    
    -- Find packageSourceCredentials section
    local creds_section = content:match("<packageSourceCredentials[^>]*>(.-)</packageSourceCredentials>")
    if not creds_section then
        return credentials
    end
    
    -- Parse each source's credentials
    for source_block in creds_section:gmatch("<(%w+)[^>]*>(.-)</%1>") do
        local source_name = source_block:match("^(%w+)")
        local block_content = source_block:match("^%w+[^>]*>(.+)")
        
        if source_name and block_content then
            local username = block_content:match('<add%s+key="Username"%s+value="([^"]+)"')
            local password = block_content:match('<add%s+key="ClearTextPassword"%s+value="([^"]+)"')
            
            if username and password then
                credentials[source_name] = {
                    username = username,
                    password = password
                }
            end
        end
    end
    
    return credentials
end

-- Parse nuget.config XML content manually if xml2lua is not available
local function parse_nuget_config_manual(content)
    local sources = {}
    local has_clear = content:match("<packageSources[^>]*>"):match("<clear")
    
    -- Find packageSources section
    local sources_section = content:match("<packageSources[^>]*>(.-)</packageSources>")
    if not sources_section then
        return sources
    end
    
    -- Parse add elements - handle any attribute order and self-closing tags
    for add_tag in sources_section:gmatch("<add[^>]+/?>") do
        local key = add_tag:match('key%s*=%s*"([^"]+)"')
        local value = add_tag:match('value%s*=%s*"([^"]+)"')
        
        if key and value then
            table.insert(sources, {
                name = key,
                url = value,
                enabled = true
            })
        end
    end
    
    -- Check disabledPackageSources to mark sources as disabled
    local disabled_section = content:match("<disabledPackageSources[^>]*>(.-)</disabledPackageSources>")
    if disabled_section then
        local disabled_keys = {}
        for key in disabled_section:gmatch('key%s*=%s*"([^"]+)"') do
            disabled_keys[key] = true
        end
        
        for _, source in ipairs(sources) do
            if disabled_keys[source.name] then
                source.enabled = false
            end
        end
    end
    
    -- Parse credentials and attach to sources
    local credentials = parse_credentials_manual(content)
    for _, source in ipairs(sources) do
        if credentials[source.name] then
            source.credentials = credentials[source.name]
        end
    end
    
    return sources
end

-- Parse credentials using xml2lua
local function parse_credentials_xml2lua(content)
    local credentials = {}
    
    local tree_handler = handler:new()
    local parser = xml2lua.parser(tree_handler)
    parser:parse(content)
    
    local root = tree_handler.root
    if not root or not root.configuration or not root.configuration.packageSourceCredentials then
        return credentials
    end
    
    local creds = root.configuration.packageSourceCredentials
    for source_name, source_creds in pairs(creds) do
        if type(source_creds) == "table" and source_creds.add then
            local adds = source_creds.add
            if type(adds) ~= "table" then
                adds = {adds}
            end
            
            local username = nil
            local password = nil
            
            for _, add in ipairs(adds) do
                if add._attr then
                    if add._attr.key == "Username" then
                        username = add._attr.value
                    elseif add._attr.key == "ClearTextPassword" then
                        password = add._attr.value
                    end
                end
            end
            
            if username and password then
                credentials[source_name] = {
                    username = username,
                    password = password
                }
            end
        end
    end
    
    return credentials
end

-- Parse nuget.config using xml2lua
local function parse_nuget_config_xml2lua(content)
    local sources = {}
    
    local tree_handler = handler:new()
    local parser = xml2lua.parser(tree_handler)
    parser:parse(content)
    
    local root = tree_handler.root
    if not root or not root.configuration then
        return sources
    end
    
    local config = root.configuration
    
    -- Get package sources
    if config.packageSources and config.packageSources.add then
        local adds = config.packageSources.add
        if type(adds) ~= "table" then
            adds = {adds}
        end
        
        for _, add in ipairs(adds) do
            if add._attr and add._attr.key and add._attr.value then
                table.insert(sources, {
                    name = add._attr.key,
                    url = add._attr.value,
                    enabled = true
                })
            end
        end
    end
    
    -- Check disabled sources
    if config.disabledPackageSources and config.disabledPackageSources.add then
        local disabled = config.disabledPackageSources.add
        if type(disabled) ~= "table" then
            disabled = {disabled}
        end
        
        local disabled_keys = {}
        for _, add in ipairs(disabled) do
            if add._attr and add._attr.key then
                disabled_keys[add._attr.key] = true
            end
        end
        
        for _, source in ipairs(sources) do
            if disabled_keys[source.name] then
                source.enabled = false
            end
        end
    end
    
    -- Parse credentials and attach to sources
    local credentials = parse_credentials_xml2lua(content)
    for _, source in ipairs(sources) do
        if credentials[source.name] then
            source.credentials = credentials[source.name]
        end
    end
    
    return sources
end

-- Find nuget.config in standard locations
function M.find_nuget_config()
    local cwd = vim.fn.getcwd()
    
    -- Check current directory first
    local paths = {
        cwd .. "/nuget.config",
        cwd .. "/NuGet.config",
        cwd .. "/NuGet.Config",
    }
    
    -- Check parent directories up to git root
    local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("%s+", "")
    if git_root and git_root ~= "" then
        local dir = cwd
        while dir ~= git_root and dir ~= "/" do
            table.insert(paths, 1, dir .. "/nuget.config")
            table.insert(paths, 1, dir .. "/NuGet.config")
            table.insert(paths, 1, dir .. "/NuGet.Config")
            dir = vim.fn.fnamemodify(dir, ":h")
        end
        table.insert(paths, 1, git_root .. "/nuget.config")
        table.insert(paths, 1, git_root .. "/NuGet.config")
        table.insert(paths, 1, git_root .. "/NuGet.Config")
    end
    
    for _, path in ipairs(paths) do
        local stat = vim.uv.fs_stat(path)
        if stat and stat.type == "file" then
            return path
        end
    end
    
    return nil
end

-- Check if Azure Artifacts Credential Provider is installed
local function is_azure_cred_provider_installed()
    local cred_provider_path = vim.fn.expand("~/.nuget/plugins/netcore/CredentialProvider.Microsoft/CredentialProvider.Microsoft.dll")
    local stat = vim.uv.fs_stat(cred_provider_path)
    return stat and stat.type == "file"
end

-- Get credentials using Azure Artifacts Credential Provider
local function get_azure_credentials(source_url)
    if not is_azure_cred_provider_installed() then
        return nil
    end

    local cred_provider_path = vim.fn.expand("~/.nuget/plugins/netcore/CredentialProvider.Microsoft/CredentialProvider.Microsoft.dll")

    -- Build the request for the credential provider
    local request = vim.fn.json_encode({
        Uri = source_url,
        IsRetry = false,
        IsNonInteractive = true,
        CanShowDialog = false
    })

    -- Call the credential provider
    local cmd = string.format(
        'dotnet "%s" -Uri "%s" -NonInteractive -CanShowDialog false 2>/dev/null',
        cred_provider_path,
        source_url
    )

    local handle = io.popen(cmd)
    if not handle then
        return nil
    end

    local response = handle:read("*a")
    handle:close()

    -- Parse the response
    if not response or response:match("^%s*$") then
        return nil
    end

    -- The credential provider outputs JSON with Username and Password
    local ok, data = pcall(vim.fn.json_decode, response)
    if not ok or not data then
        return nil
    end

    if data.Username and data.Password then
        return {
            username = data.Username,
            password = data.Password
        }
    end

    return nil
end

-- Get credentials from environment variables
-- Format: UNIPACKAGE_NUGET_<SOURCE_NAME>_USERNAME and UNIPACKAGE_NUGET_<SOURCE_NAME>_TOKEN
local function get_env_credentials(source_name)
    local env_name = source_name:gsub("[^%w]", "_"):upper()
    local username = os.getenv("UNIPACKAGE_NUGET_" .. env_name .. "_USERNAME")
    local token = os.getenv("UNIPACKAGE_NUGET_" .. env_name .. "_TOKEN")

    if not token then
        token = os.getenv("UNIPACKAGE_NUGET_" .. env_name .. "_PASSWORD")
    end

    if username and token then
        return {
            username = username,
            password = token
        }
    end

    return nil
end

-- Parse nuget.config and return package sources
function M.get_package_sources()
    local config_path = M.find_nuget_config()
    if not config_path then
        return nil
    end
    
    local file = io.open(config_path, "r")
    if not file then
        return nil
    end
    
    local content = file:read("*a")
    file:close()
    
    local sources
    if try_load_xml2lua() then
        sources = parse_nuget_config_xml2lua(content)
    else
        sources = parse_nuget_config_manual(content)
    end
    
    -- Check for credentials in priority order:
    -- 1. Environment variables (highest priority)
    -- 2. Azure Artifacts Credential Provider
    -- 3. nuget.config file (lowest priority)
    for _, source in ipairs(sources) do
        local env_creds = get_env_credentials(source.name)
        if env_creds then
            source.credentials = env_creds
            source.credentials_source = "environment"
        else
            -- Try Azure Artifacts Credential Provider for Azure DevOps feeds
            if source.url:match("dev%.azure%.com") or source.url:match("visualstudio%.com") then
                local azure_creds = get_azure_credentials(source.url)
                if azure_creds then
                    source.credentials = azure_creds
                    source.credentials_source = "azure-credential-provider"
                end
            end
        end
    end
    
    -- Filter to only enabled sources
    local enabled_sources = {}
    for _, source in ipairs(sources) do
        if source.enabled then
            table.insert(enabled_sources, source)
        end
    end
    
    return enabled_sources
end

-- Debug function to help troubleshoot
function M.debug()
    local config_path = M.find_nuget_config()
    local result = {
        config_path = config_path,
        sources = nil,
        error = nil
    }
    
    if not config_path then
        result.error = "No nuget.config found"
        return result
    end
    
    local file = io.open(config_path, "r")
    if not file then
        result.error = "Cannot read config file: " .. config_path
        return result
    end
    
    local content = file:read("*a")
    file:close()
    
    result.raw_content_preview = content:sub(1, 500)
    
    local sources
    if try_load_xml2lua() then
        sources = parse_nuget_config_xml2lua(content)
        result.parser = "xml2lua"
    else
        sources = parse_nuget_config_manual(content)
        result.parser = "manual"
    end
    
    -- Check environment variables for credentials
    for _, source in ipairs(sources) do
        local env_creds = get_env_credentials(source.name)
        if env_creds then
            source.credentials = env_creds
            source.credentials_source = "environment"
        elseif source.credentials then
            source.credentials_source = "nuget.config"
        end
    end
    
    result.sources = sources
    result.enabled_sources = {}
    for _, source in ipairs(sources) do
        if source.enabled then
            table.insert(result.enabled_sources, source)
        end
    end
    
    return result
end

-- Get the service index URL for NuGet v3 API
function M.get_service_index_url(source_url)
    -- If it's already an index.json, return as-is
    if source_url:match("index%.json$") then
        return source_url
    end
    
    -- Try common patterns
    if source_url:match("/$") then
        return source_url .. "v3/index.json"
    end
    
    return source_url .. "/v3/index.json"
end

-- Get authentication headers for a source
function M.get_auth_headers(source)
    if not source.credentials then
        return nil
    end
    
    local username = source.credentials.username or ""
    local password = source.credentials.password or ""
    local auth_string = username .. ":" .. password
    
    -- Use system base64 command for reliability
    local handle = io.popen("printf '%s' " .. vim.fn.shellescape(auth_string) .. " | base64 -w 0")
    local encoded = handle and handle:read("*a") or ""
    if handle then handle:close() end
    
    -- Fallback to Lua implementation if system command fails
    if not encoded or encoded == "" then
        -- Pure Lua base64 encode
        local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
        local function b64encode(data)
            return ((data:gsub('.', function(x) 
                local r, b = '', x:byte()
                for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
                return r
            end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
                if (#x < 6) then return '' end
                local c = 0
                for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
                return b64chars:sub(c + 1, c + 1)
            end) .. ({'', '==', '='})[#data % 3 + 1])
        end
        encoded = b64encode(auth_string)
    end
    
    return {
        ["Authorization"] = "Basic " .. encoded
    }
end

-- Show nuget.config status in a floating window
function M.status()
    local config_path = M.find_nuget_config()
    local lines = {}
    local highlights = {}
    
    -- Header
    table.insert(lines, "NuGet Configuration Status")
    table.insert(lines, string.rep("=", 50))
    table.insert(lines, "")
    table.insert(highlights, {line = 0, col = 0, end_col = 26, hl_group = "Title"})
    
    -- Config file location
    if config_path then
        table.insert(lines, "Config file found: ✓")
        table.insert(lines, "  Path: " .. config_path)
        table.insert(highlights, {line = #lines - 2, col = 19, end_col = 20, hl_group = "DiagnosticOk"})
    else
        table.insert(lines, "Config file found: ✗")
        table.insert(lines, "  No nuget.config found in project or parent directories")
        table.insert(highlights, {line = #lines - 2, col = 19, end_col = 20, hl_group = "DiagnosticError"})
    end
    table.insert(lines, "")
    
    -- Sources
    local sources = M.get_package_sources()
    if sources and #sources > 0 then
        table.insert(lines, "Package Sources:")
        table.insert(highlights, {line = #lines - 1, col = 0, end_col = 16, hl_group = "Label"})
        
        for _, source in ipairs(sources) do
            local cred_status = ""
            if source.credentials then
                if source.credentials_source == "environment" then
                    cred_status = " 🔐 (env)"
                elseif source.credentials_source == "azure-credential-provider" then
                    cred_status = " 🔐 (azure)"
                else
                    cred_status = " 🔐 (config)"
                end
            end

            table.insert(lines, string.format("  • %s%s", source.name, cred_status))
            table.insert(lines, string.format("    URL: %s", source.url))

            if source.credentials then
                local hl_line = #lines - 2
                local cred_pos = string.find(lines[hl_line], "🔐")
                if cred_pos then
                    local cred_start = cred_pos - 1
                    table.insert(highlights, {line = hl_line, col = cred_start, end_col = cred_start + 11, hl_group = "DiagnosticOk"})
                end
            end
        end
    elseif config_path then
        table.insert(lines, "Package Sources: None enabled")
        table.insert(highlights, {line = #lines - 1, col = 0, end_col = 15, hl_group = "Label"})
    end
    table.insert(lines, "")
    
    -- Environment variables check
    table.insert(lines, "Environment Variables Checked:")
    table.insert(highlights, {line = #lines - 1, col = 0, end_col = 29, hl_group = "Label"})
    
    local env_vars_found = false
    for _, source in ipairs(sources or {}) do
        local source_name = source.name:gsub("[^%w]", "_"):upper()
        local username = os.getenv("UNIPACKAGE_NUGET_" .. source_name .. "_USERNAME")
        local token = os.getenv("UNIPACKAGE_NUGET_" .. source_name .. "_TOKEN") or os.getenv("UNIPACKAGE_NUGET_" .. source_name .. "_PASSWORD")
        
        if username or token then
            env_vars_found = true
            table.insert(lines, string.format("  • UNIPACKAGE_NUGET_%s_USERNAME: %s", source_name, username and "✓" or "✗"))
            table.insert(lines, string.format("  • UNIPACKAGE_NUGET_%s_TOKEN: %s", source_name, token and "✓" or "✗"))
            
            local hl_line = #lines - 2
            local status_col = string.find(lines[hl_line], ":") + 1
            if username then
                table.insert(highlights, {line = hl_line, col = status_col, end_col = status_col + 1, hl_group = "DiagnosticOk"})
            end
            if token then
                table.insert(highlights, {line = hl_line + 1, col = status_col, end_col = status_col + 1, hl_group = "DiagnosticOk"})
            end
        end
    end
    
    if not env_vars_found then
        table.insert(lines, "  No UNIPACKAGE_NUGET_* environment variables set")
    end
    table.insert(lines, "")
    
    -- Azure Credential Provider status
    table.insert(lines, "Azure Credential Provider:")
    table.insert(highlights, {line = #lines - 1, col = 0, end_col = 25, hl_group = "Label"})
    if is_azure_cred_provider_installed() then
        table.insert(lines, "  Status: ✓ Installed")
        table.insert(highlights, {line = #lines - 1, col = 10, end_col = 11, hl_group = "DiagnosticOk"})
    else
        table.insert(lines, "  Status: ✗ Not installed")
        table.insert(highlights, {line = #lines - 1, col = 10, end_col = 11, hl_group = "DiagnosticError"})
        table.insert(lines, "  Install: curl -fsSL https://aka.ms/install-artifacts-credprovider.sh | bash")
    end
    table.insert(lines, "")

    -- Help text
    table.insert(lines, "Notes:")
    table.insert(highlights, {line = #lines - 1, col = 0, end_col = 5, hl_group = "Label"})
    table.insert(lines, "  • 🔐 (env)    = Credentials from environment variables")
    table.insert(lines, "  • 🔐 (azure)  = Credentials from Azure credential provider")
    table.insert(lines, "  • 🔐 (config) = Credentials from nuget.config file")
    table.insert(lines, "  • Priority: env > azure > config")
    
    -- Create floating window
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    -- Apply highlights
    for _, hl in ipairs(highlights) do
        vim.api.nvim_buf_add_highlight(buf, -1, hl.hl_group, hl.line, hl.col, hl.end_col)
    end
    
    -- Set buffer options
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "unipackage-nuget"
    
    -- Calculate window size
    local width = 80
    local height = math.min(#lines + 2, vim.o.lines - 4)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    
    -- Open floating window
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " UniPackage NuGet Config ",
        title_pos = "center",
    })
    
    -- Set window options
    vim.wo[win].cursorline = true
    vim.wo[win].wrap = true
    
    -- Add keymap to close
    vim.keymap.set("n", "q", function()
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true, silent = true })
    vim.keymap.set("n", "<Esc>", function()
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true, silent = true })
end

return M
# Developer Documentation

Technical documentation for contributing to and extending UniPackage.nvim.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Module Structure](#module-structure)
- [Interfaces](#interfaces)
- [Development Guidelines](#development-guidelines)
- [Performance Considerations](#performance-considerations)
- [Error Handling](#error-handling)

## Architecture Overview

UniPackage is a modular Neovim plugin that provides unified package management across multiple languages and package managers. The system uses a consistent interface pattern with dynamic module loading to support extensible package manager integration.

### Key Design Principles

1. **Modular Design**: Each package manager is implemented as a separate module with a consistent interface
2. **Dynamic Loading**: Modules are loaded only when needed via `pcall(require, ...)`
3. **Priority-Based Selection**: Lock file detection > user preference > system availability
4. **Configuration System**: Centralized configuration with validation and default values

## Module Structure

```
lua/unipackage/
├── init.lua                 -- Main entry point
├── health.lua              -- Health check module (:checkhealth)
├── core/
│   ├── init.lua            -- Module exports and commands
│   ├── config.lua          -- Configuration system
│   ├── constants.lua       -- Centralized constants
│   ├── modules.lua         -- Shared module loader
│   ├── actions.lua         -- Package operations
│   ├── ui.lua              -- User interface
│   ├── version_ui.lua      -- Version selection UI
│   ├── terminal.lua        -- Terminal abstraction
│   └── error.lua           -- Error handling utilities
├── languages/
│   ├── go/
│   │   └── go.lua         -- Go module support
│   ├── dotnet/
│   │   └── dotnet.lua     -- .NET project support
│   └── javascript/
│       ├── bun.lua        -- Bun support
│       ├── npm.lua        -- NPM support
│       ├── pnpm.lua       -- PNPM support
│       └── yarn.lua       -- Yarn support
└── utils/
    ├── cache.lua          -- Optimized LRU cache
    ├── http.lua           -- HTTP utilities
    ├── npm_search.lua     -- NPM registry search
    ├── nuget_search.lua   -- NuGet registry search
    ├── npm_versions.lua   -- NPM version fetching
    ├── nuget_versions.lua -- NuGet version fetching
    └── version_utils.lua  -- Shared version utilities
```

## Interfaces

### Package Manager Interface

All package manager modules must implement:

#### `run_command(args)`

```lua
--- Executes package manager commands
-- @param args table: Command arguments (e.g., {"install", "package"})
-- @return void: Executes command via ToggleTerm
function M.run_command(args)
    local Terminal = require("toggleterm.terminal").Terminal
    local runner = Terminal:new({
        direction = "float",
        close_on_exit = false,
        hidden = true,
    })
    local cmd = "manager " .. table.concat(args, " ")
    runner.cmd = cmd
    runner:toggle()
end
```

#### `get_installed_packages()`

```lua
--- Gets list of installed packages
-- @return table: Array of package names
function M.get_installed_packages()
    local handle = io.popen("manager list --flags 2>/dev/null")
    if not handle then return {} end
    
    local output = handle:read("*a")
    handle:close()
    
    local packages = {}
    for line in output:gmatch("[^\r\n]+") do
        -- Parse package@version patterns
        -- Filter out manager itself
        -- Return clean package names
    end
    
    return packages
end
```

### Configuration Interface

#### `setup(user_config)`

```lua
--- Configures the plugin
-- @param user_config table: User configuration options
-- @return boolean: Success status
function M.setup(user_config)
    -- Validate user configuration
    -- Merge with defaults
    -- Store in global variable
    -- Return success status
end
```

## Development Guidelines

### Adding New Package Managers

1. **Create Module File** in appropriate language directory
2. **Update Configuration** in `core/config.lua` with detection patterns
3. **Test Interface** to ensure standard functions work

### Priority Resolution Algorithm

```lua
function resolve_preferred_manager()
    local detected = get_detected_managers()
    local priorities = config.get_priority_order()
    
    -- 1. Lock file priority
    for _, manager in ipairs(priorities) do
        if vim.tbl_contains(detected, manager) then
            return manager
        end
    end
    
    -- 2. System availability fallback
    if config.fallback_to_any then
        for _, manager in ipairs(priorities) do
            if vim.fn.executable(manager) == 1 then
                return manager
            end
        end
    end
    
    return nil
end
```

### Validation Rules

```lua
local validation_rules = {
    -- Type checking
    package_managers = "table",
    search_batch_size = "number",
    fallback_to_any = "boolean",
    warn_on_fallback = "boolean",
    version_selection = "table",
    
    -- Value validation
    package_manager_names = {"bun", "go", "dotnet", "npm", "pnpm", "yarn"},
    search_batch_size_range = function(n) return n >= 1 and n <= 100 end,
    non_empty_arrays = function(arr) return #arr > 0 end,
    version_selection_languages = {"javascript", "dotnet", "go"}
}
```

## Version Selection System

### Overview
The version selection system allows users to choose specific package versions through a two-step UI:
1. Select major version (e.g., "18.x")
2. Select specific version (e.g., "18.2.0")

### Architecture

```
User selects package from search
        ↓
Check: config.is_version_selection_enabled(language)
        ↓
    ┌─────────────┐
    │   Enabled   │────→ Fetch versions from registry
    └─────────────┘            ↓
    ┌─────────────┐     Group by major version
    │   Disabled  │────→ Install @latest
    └─────────────┘
                               ↓
                        Show major version selection
                               ↓
                        Show specific version selection
                               ↓
                        Install selected version
```

### Implementation

#### version_ui.lua
Central UI module for version selection:

```lua
-- NPM version selection (JavaScript packages)
function M.select_npm_version(package_name, manager, on_complete)
    -- Shows notification: "[~] Searching versions for: {package}"
    -- Fetches versions via npm_versions module
    -- Presents two-step selection UI
    -- Calls on_complete(version) or on_complete("latest") on cancel
end

-- NuGet version selection (.NET packages)
function M.select_nuget_version(package_id, project, on_complete)
    -- Similar flow for NuGet packages
end
```

#### version_utils.lua
Shared utilities for version operations:

```lua
-- Parse semantic version
function M.parse_semver(version) → {major, minor, patch, prerelease}

-- Compare two versions
function M.compare_versions(v1, v2) → -1, 0, 1

-- Group versions by major
function M.group_by_major(versions) → {major: {versions, latest}}

-- Filter pre-releases
function M.filter_prereleases(versions, include_prerelease) → filtered_versions

-- Format for display
function M.format_major_group(major, group) → "18.x (Latest: 18.2.0, 45 versions)"
function M.format_version(version) → "18.2.0" or "18.2.0-beta.1"
```

#### npm_versions.lua / nuget_versions.lua
Registry-specific implementations:

```lua
-- Fetch and cache versions
function M.get_versions_by_major_async(package, include_prerelease, callback)
    -- Returns: {major_version: {versions, latest}}
end

function M.get_versions_for_major_async(package, major, include_prerelease, max_results, callback)
    -- Returns: [version_strings]
end
```

### Configuration

```lua
version_selection = {
    enabled = false,                    -- Master switch
    languages = {                       -- Per-language control
        javascript = true,              -- Enable for npm/yarn/pnpm/bun
        dotnet = true,                  -- Enable for NuGet
        go = false,                     -- Disabled (uses go.mod)
    },
    include_prerelease = false,         -- Exclude alpha/beta/rc
    max_versions_shown = 20,            -- Limit for expanded view
}
```

### Adding Version Selection to New Languages

1. Create `{language}_versions.lua` in `utils/`
2. Implement registry-specific fetching
3. Use `version_utils` for shared operations
4. Add language to `version_selection.languages` in config
5. Call version selection from UI module

## Performance Considerations

### Module Loading

- **Lazy loading**: Modules loaded only when needed
- **Error handling**: Graceful degradation on load failures
- **Caching**: Configuration cached after first load

### Command Execution

- **Terminal reuse**: ToggleTerm instances properly managed
- **Async operations**: Non-blocking command execution
- **Output parsing**: Optimized regex patterns

### Memory Management

- **Garbage collection**: Proper cleanup of temporary objects
- **Handle management**: Terminal instances cleaned up
- **String operations**: Optimized pattern matching

### Caching System

- **LRU Cache**: O(1) operations with index tracking
- **Memory Limits**: 10MB max with 100 entry limit
- **JSON Limits**: 10MB max response size (increased for packages with many versions)
- **TTL**: 30 minutes for search results and version lists
- **Version Cache**: Separate caching for npm/nuget version lists

## Error Handling

### Module Loading Errors

```lua
-- Graceful fallback
local ok, module = pcall(require, "unipackage." .. manager)
if not ok then
    vim.notify(string.format("Package manager '%s' not available", manager), vim.log.levels.ERROR)
    return nil
end
```

### Command Execution Errors

```lua
-- Terminal error handling
local ok, result = pcall(runner.toggle, runner)
if not ok then
    vim.notify("Failed to execute package manager command", vim.log.levels.ERROR)
end
```

### Configuration Errors

```lua
-- Validation with detailed messages
local errors = validate_config(user_config)
if #errors > 0 then
    vim.notify("Configuration errors:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
    return false
end
```

## Data Flow

### Package Manager Selection

```
Project Directory
├── bun.lock           → Detect BUN
├── package-lock.json   → Detect NPM
├── pnpm-lock.yaml      → Detect PNPM
└── yarn.lock           → Detect YARN

Lock Files + User Priority + System Availability
├── Detection (config.get_detected_managers())
├── Priority (config.get_priority_order())
├── Resolution (config.get_preferred_manager())
└── Selection (utils.get_manager_for_project())
```

### Command Execution

```
User Action
├── UI Dialog (ui.lua)
├── Action Function (actions.lua)
├── Module Loading (get_manager_module())
├── Command Execution (run_command())
└── Terminal (ToggleTerm)
```

## Testing Strategy

### Unit Testing

```lua
-- Test module interface
local module = require("unipackage.new_manager")
assert(type(module.run_command) == "function")
assert(type(module.get_installed_packages) == "function")

-- Test configuration validation
local ok = config.setup({package_managers = {"new_manager"}})
assert(ok == true)
```

### Integration Testing

```bash
# Test with different lock files
mkdir test-project && cd test-project
touch new_manager.lock && nvim -c "require('unipackage').package_menu()"

# Test priority resolution
touch bun.lock && touch new_manager.lock
nvim -c "require('unipackage').get_preferred_manager()"
```

## Extensibility

### Interface Contracts

The system is designed for easy extension:
- **Standard interface**: All managers implement same function signatures
- **Dynamic loading**: New managers automatically integrated
- **Configuration**: New managers added to validation and priority lists
- **UI integration**: New managers automatically appear in menus

### Future Enhancements

Potential areas for expansion:
- **Workspace support**: Advanced monorepo operations
- **Dependency trees**: Visual dependency relationships
- **Version management**: Package upgrade and downgrade operations
- **Performance modes**: Parallel operations, background prefetching
- **Version Selection Extensions**:
  - Version range selection (e.g., ^18.0.0, ~18.2.0)
  - Changelog integration
  - Security vulnerability checking
  - Compatibility matrix display

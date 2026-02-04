# UniPackage Architecture

Technical documentation for the UniPackage Neovim plugin architecture, interfaces, and development guidelines.

## Overview

UniPackage is a modular Neovim plugin that provides unified package management across multiple JavaScript package managers (bun, pnpm, npm, yarn). The system uses a consistent interface pattern with dynamic module loading to support extensible package manager integration.

## Module Structure

```
unipackage/
├── README.md               # User documentation (installation, usage, configuration)
├── ARCHITECTURE.md        # This file - technical documentation
├── CONTRIBUTING.md          # Development guidelines (optional)
├── LICENSE                  # MIT license
├── lua/                    # Main source code
│   ├── init.lua           # Main entry point, setup function, vim commands
│   ├── config.lua          # Configuration system, validation, priority resolution
│   ├── utils.lua           # Package manager detection, file utilities
│   ├── actions.lua          # Dynamic package manager operations, abstraction layer
│   ├── ui.lua              # Interactive dialogs, menu system
│   ├── bun.lua             # Bun package manager integration
│   ├── npm.lua             # NPM package manager integration
│   ├── pnpm.lua            # PNPM package manager integration
│   └── yarn.lua            # Yarn package manager integration
└── .git/                   # Version control
```

## Architecture Principles

### 1. Modular Design
Each package manager is implemented as a separate module with a consistent interface:
```lua
-- Standard interface contract
function M.run_command(args)           -- Execute commands via ToggleTerm
function M.get_installed_packages()     -- Parse package lists and return arrays
```

### 2. Dynamic Loading
The system uses dynamic module loading to support any package manager:
```lua
-- In actions.lua
local function get_manager_module(manager)
    local ok, module = pcall(require, "unipackage." .. manager)
    return ok and module or nil
end
```

### 3. Priority-Based Selection
Package manager selection follows a deterministic order:
1. **Lock file detection** (highest priority)
2. **User preference** (within available managers)
3. **System availability** (fallback when no lock files)
4. **Configurable behavior** (fallback settings)

### 4. Configuration System
Centralized configuration with validation and default values:
```lua
-- Default configuration
local default_config = {
    package_managers = {"bun", "pnpm", "npm", "yarn"},
    auto_detect = true,
    fallback_to_any = true,
    warn_on_fallback = true
}
```

## Interfaces

### Package Manager Interface

All package manager modules must implement:

#### run_command(args)
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

#### get_installed_packages()
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

#### setup(user_config)
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

## Module Responsibilities

### init.lua - Main Entry Point
- **Setup function**: `M.setup(user_config)` for plugin configuration
- **Command registration**: All vim commands (`:UniPackageMenu`, etc.)
- **Legacy compatibility**: Backward-compatible function exports
- **Module coordination**: Imports and coordinates all other modules

### config.lua - Configuration System
- **Default values**: Sensible defaults for all options
- **Validation**: Type checking and value validation
- **Priority resolution**: Lock file > user preference > system availability
- **Lock file patterns**: Detection patterns for all managers
- **Global storage**: `vim.g.unipackage_config` for external access

### utils.lua - Detection & Utilities
- **File system**: `file_exists()`, directory utilities
- **Lock file detection**: Based on configured patterns
- **Manager detection**: `get_detected_managers()`, `get_preferred_manager()`
- **Availability checking**: System-level package manager availability

### actions.lua - Abstraction Layer
- **Dynamic loading**: `get_manager_module(manager)` for any manager
- **Unified operations**: `install_packages()`, `uninstall_packages()`, `list_packages()`
- **Command mapping**: npm="uninstall", others="remove"
- **Error handling**: Graceful degradation when managers unavailable

### ui.lua - User Interface
- **Interactive dialogs**: vim.ui.input(), vim.ui.select()
- **Safe wrapper functions**: Handle closure scoping issues
- **Menu system**: `package_menu()` with priority indicators
- **Context awareness**: Shows detected managers and preferred choice
- **Error messages**: User-friendly feedback for all operations

### Package Manager Modules

#### bun.lua
- **Commands**: `bun install`, `bun remove`, `bun list`
- **Lock files**: `bun.lock`, `bun.lockb`
- **Output parsing**: Tree format with package@version lines
- **Integration**: Uses ToggleTerm for command execution

#### npm.lua
- **Commands**: `npm install`, `npm uninstall`, `npm list --depth=0`
- **Lock files**: `package-lock.json`
- **Output parsing**: Complex tree format with unicode characters
- **Special handling**: Header filtering, dependency tree parsing

#### pnpm.lua
- **Commands**: `pnpm install`, `pnpm remove`, `pnpm list --depth=0`
- **Lock files**: `pnpm-lock.yaml`
- **Output parsing**: Cleaner format with optional workspace support
- **Additional**: `is_workspace()` function for monorepo detection

#### yarn.lua
- **Commands**: `yarn install`, `yarn remove`, `yarn list --depth=0`
- **Lock files**: `yarn.lock`, `.yarnrc.yml`
- **Output parsing**: Tree format with version header line
- **Special handling**: Header filtering, Yarn-specific tree symbols

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

### Package Listing
```
Manager Execution
├── Command: "manager list --flags"
├── Output Capture (io.popen())
├── Text Parsing (get_installed_packages())
├── Package Extraction (regex patterns)
└── UI Display (vim.ui.select())
```

## Configuration System

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
    auto_detect = "boolean",
    fallback_to_any = "boolean",
    warn_on_fallback = "boolean",
    
    -- Value validation
    package_manager_names = {"bun", "npm", "pnpm", "yarn"},
    non_empty_arrays = function(arr) return #arr > 0 end
}
```

## Development Guidelines

### Adding New Package Managers

#### 1. Create Module File
```lua
-- lua/new_manager.lua
local M = {}

function M.run_command(args)
    -- Implementation for command execution
end

function M.get_installed_packages()
    -- Implementation for package parsing
end

return M
```

#### 2. Update Configuration
```lua
-- In config.lua
local detection_patterns = {
    existing_manager = {"existing.lock"},
    new_manager = {"new_manager.lock"},  -- Add this
}

local valid_managers = {"bun", "npm", "pnpm", "yarn", "new_manager"}  -- Add this
```

#### 3. Update Actions
- No changes needed if standard interface implemented
- Special command handling in `uninstall_packages()` if needed
- Integration testing with dynamic loading

### Testing Strategy

#### Unit Testing
```lua
-- Test module interface
local module = require("unipackage.new_manager")
assert(type(module.run_command) == "function")
assert(type(module.get_installed_packages) == "function")

-- Test configuration validation
local ok = config.setup({package_managers = {"new_manager"}})
assert(ok == true)
```

#### Integration Testing
```bash
# Test with different lock files
mkdir test-project && cd test-project
touch new_manager.lock && nvim -c "require('unipackage').package_menu()"

# Test priority resolution
touch bun.lock && touch new_manager.lock
nvim -c "require('unipackage').get_preferred_manager()"
```

#### Command Testing
```bash
# Test all operations for new manager
nvim -c "
local manager = 'new_manager'
require('unipackage.actions').install_packages({'package'}, manager)
require('unipackage.actions').uninstall_packages({'package'}, manager)
require('unipackage.actions').list_packages(manager)
"
```

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
- **Package search**: Registry integration for package discovery
- **Version management**: Package upgrade and downgrade operations
- **Performance modes**: Cache integration, parallel operations

This architecture provides a robust, extensible foundation for package management across multiple JavaScript ecosystems while maintaining clean separation of concerns and consistent user experience.
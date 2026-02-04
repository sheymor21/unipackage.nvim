# UniPackage

UniPackage is a unified package management plugin for Neovim that supports multiple JavaScript package managers (bun, pnpm, npm, yarn) with intelligent priority-based selection and lock file detection.

## Features
- 🚀 **Multi-Manager Support**: bun, pnpm, npm, yarn with automatic detection
- 🎯 **Smart Priority**: Modern → Traditional ordering (bun > pnpm > npm > yarn)
- 🔍 **Lock File Priority**: Respects existing project setup over user preferences
- ⚙️  **Configurable**: User-defined priority and fallback behavior
- 🖥️ **Interactive Menu**: Single entry point with project context
- 🔄 **Backward Compatible**: All existing commands work unchanged

## Quick Start

### Installation
```lua
-- Using your favorite plugin manager
use {
    "sheymor/unipackage",
    config = function()
        -- Plugin automatically works out of box
        require("unipackage")
    end
}
```

### Basic Usage
```lua
-- Works out of box with default priorities
require('unipackage')

-- Or configure custom priorities
require('unipackage').setup({
    package_managers = {'bun', 'pnpm', 'npm', 'yarn'}
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:UniPackageMenu` | Interactive package management menu |
| `:UniPackageInstall` | Install packages with auto-detection |
| `:UniPackageUninstall` | Remove packages with selection |
| `:UniPackageList` | List installed packages |
| `:UniPackageSetup` | Configure plugin settings |

## Project Detection

UniPackage automatically detects package managers based on lock files:

| Manager | Lock File | Priority |
|---------|------------|----------|
| bun     | `bun.lock` | 1 (Highest) |
| pnpm    | `pnpm-lock.yaml` | 2 |
| npm      | `package-lock.json` | 3 |
| yarn     | `yarn.lock` | 4 (Lowest) |

### Detection Scenarios
```bash
# Single lock file
yarn.lock present → Uses YARN

# Multiple lock files
bun.lock + package-lock.json → Uses BUN (higher priority)

# No lock files
No lock files → Uses highest priority available manager
```

## Configuration

### Default Configuration
```lua
{
    package_managers = {"bun", "pnpm", "npm", "yarn"},
    auto_detect = true,
    fallback_to_any = true,
    warn_on_fallback = true
}
```

### Setup Examples
```lua
-- Modern priority (default)
require('unipackage').setup({
    package_managers = {'bun', 'pnpm', 'npm', 'yarn'}
})

-- Traditional priority
require('unipackage').setup({
    package_managers = {'npm', 'yarn', 'pnpm', 'bun'}
})

-- Performance-first
require('unipackage').setup({
    package_managers = {'pnpm', 'bun', 'npm', 'yarn'}
})

-- Disable fallback
require('unipackage').setup({
    package_managers = {'bun', 'pnpm', 'npm', 'yarn'},
    fallback_to_any = false
})

-- Runtime configuration
:UniPackageSetup '{"package_managers": ["bun", "pnpm"]}'
```

### Configuration Options

| Option | Type | Default | Description |
|---------|--------|----------|-------------|
| `package_managers` | table | `{"bun", "pnpm", "npm", "yarn"}` | Priority order for package managers |
| `auto_detect` | boolean | `true` | Automatic lock file detection |
| `fallback_to_any` | boolean | `true` | Use any available manager when no lock file |
| `warn_on_fallback` | boolean | `true` | Show warning when using fallback |
| `require_explicit` | boolean | `false` | Require explicit setup before using |

## Architecture

UniPackage uses a modular architecture with consistent interfaces across all package managers:

```
lua/
├── init.lua          # Main entry point + setup function
├── config.lua        # Configuration system + validation
├── utils.lua          # Package manager detection + utilities
├── actions.lua        # Dynamic package manager operations
├── ui.lua             # User interface dialogs + menu
└── [manager].lua     # Individual package managers
    ├── bun.lua           # Bun command execution + parsing
    ├── pnpm.lua          # PNPM command execution + parsing
    ├── npm.lua           # NPM command execution + parsing
    └── yarn.lua          # Yarn command execution + parsing
```

## Priority Resolution

1. **Lock file detection** takes priority over user preference
2. **User priority** determines order within available managers
3. **System availability** used when no lock files exist
4. **Fallback behavior** configurable via settings

## Usage Examples

### Daily Workflow
```vim
" Open interactive menu
:UniPackageMenu

" Install specific package
:UniPackageInstall
Enter package(s) to install: react@18 typescript

" Remove package
:UniPackageUninstall
Select package(s) to uninstall: • react

" List packages
:UniPackageList
```

### Project Switching
```bash
# Working in bun project
cd my-bun-project
:UniPackageMenu  # Uses BUN

# Switch to npm project
cd my-npm-project
:UniPackageMenu  # Uses NPM

# Project with multiple lock files
cd mixed-project  # bun.lock + package-lock.json
:UniPackageMenu  # Uses BUN (higher priority)
```

## Troubleshooting

### Common Issues

#### "No supported package manager detected"
- **Cause**: No lock file found (bun.lock, pnpm-lock.yaml, package-lock.json, yarn.lock)
- **Solution**: Install desired package manager or create lock file
- **Example**: `npm install` or `yarn install`

#### "Package manager not available"
- **Cause**: Package manager not installed system-wide
- **Solution**: Install package manager
- **Example**: `npm install -g pnpm`

#### Configuration errors
```lua
-- Validate configuration
local ok = require('unipackage').setup({
    package_managers = {'bun', 'npm'}  -- Valid
})

-- Invalid configuration
local ok = require('unipackage').setup({
    package_managers = 'invalid'  -- Error with details
})
```

#### Priority conflicts
```lua
-- Check current priority
lua -e "print(require('unipackage').get_config('package_managers'))"

-- Change priority
require('unipackage').setup({
    package_managers = {'pnpm', 'bun', 'npm', 'yarn'}
})
```

## For Developers

For detailed technical documentation, see **[ARCHITECTURE.md](ARCHITECTURE.md)**

### Quick Developer Reference
```lua
-- Adding new package manager
function M.run_command(args)      -- Required: Execute commands via ToggleTerm
function M.get_installed_packages() -- Required: Parse package lists and return arrays

-- Current module interfaces
require('unipackage.bun')    -- Bun integration
require('unipackage.npm')    -- NPM integration
require('unipackage.pnpm')   -- PNPM integration
require('unipackage.yarn')   -- Yarn integration
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
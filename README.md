# UniPackage

A unified package management plugin for Neovim supporting multiple languages and package managers with intelligent detection, search capabilities, and project-aware operations.

## Features

- 🚀 **Multi-Language Support**: JavaScript/TypeScript (bun, pnpm, npm, yarn), Go, and .NET
- 🔍 **Package Search**: Search npm and NuGet registries with intelligent filtering
- 📜 **Lazy Loading**: Paginated search results with configurable batch size
- ⚡ **High Performance**: Async HTTP requests, in-memory caching, and optimized operations
- 🎯 **Smart Priority**: Language-aware priority system with automatic detection
- 📁 **Project Selection**: Multi-project support for .NET solutions
- 🏷️ **Framework Compatibility**: .NET package filtering by TargetFramework
- 🔍 **Lock File Priority**: Respects existing project setup over user preferences
- ⚙️ **Configurable**: User-defined priority, fallback behavior, and search batch size
- 🖥️ **Interactive UI**: Native Neovim UI with fuzzy finding and loading indicators
- 💾 **Intelligent Caching**: In-memory LRU cache with size limits and persistence

## Supported Package Managers

| Language | Managers | Detection Files |
|----------|----------|----------------|
| JavaScript/TypeScript | bun, pnpm, npm, yarn | `package.json`, lock files |
| Go | go | `go.mod`, `go.sum`, `go.work` |
| .NET | dotnet | `.sln`, `.csproj`, `.fsproj`, `.vbproj` |

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "sheymor/unipackage.nvim",
    dependencies = {
        "akinsho/toggleterm.nvim", -- Required for terminal integration
        "nvim-lua/plenary.nvim",   -- Required for async HTTP operations
    },
    config = function()
        require("unipackage").setup()
    end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "sheymor/unipackage.nvim",
    requires = { 
        "akinsho/toggleterm.nvim",
        "nvim-lua/plenary.nvim",
    },
    config = function()
        require("unipackage").setup()
    end,
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'akinsho/toggleterm.nvim'
Plug 'sheymor/unipackage.nvim'
```

```lua
-- In your init.lua or config
require("unipackage").setup()
```

## Quick Start

### Basic Usage

```lua
-- Works out of the box with default priorities
require("unipackage").setup()

-- Or configure custom priorities
require("unipackage").setup({
    package_managers = { "bun", "go", "dotnet", "pnpm", "npm", "yarn" }
})
```

### Default Configuration
```lua
{
    -- Package manager priority order
    package_managers = { "bun", "go", "dotnet", "pnpm", "npm", "yarn" },

    -- Search results configuration
    search_batch_size = 20,   -- Number of items to show per batch in search results (1-100)

    -- Fallback behavior
    fallback_to_any = true,   -- If no lock file found, use any available manager
    warn_on_fallback = true,  -- Show warning when using fallback
}
```

## Commands

| Command | Description |
|---------|-------------|
| `:UniPackageMenu` | Interactive package management menu |
| `:UniPackageInstall` | Install packages with search support |
| `:UniPackageUninstall` | Remove packages with selection |
| `:UniPackageList` | List installed packages |
| `:UniPackageSetup` | Configure plugin settings |
| `:UniPackageDebug` | Show detection debug information |
| `:UniPackageClearCache` | Clear all caches |
| `:checkhealth unipackage` | Run health checks |

## Usage Examples

### JavaScript/TypeScript Projects

```vim
" Open menu (auto-detects package manager)
:UniPackageMenu

" Install with search (lazy loading enabled)
:UniPackageInstall
> Type: react
> Search results appear (20 items at a time)...
> Navigate: ⬅️ Previous batch / 📥 Load more...
> Select: react @ 18.2.0
> Installs: npm install react@latest

" Direct install with version
:UniPackageInstall
> Enter: react@18.2.0

" Direct install latest
:UniPackageInstall
> Enter: react@
> Installs: react@latest
```

### Go Projects

```vim
" Go works similarly with mod tidy support
:UniPackageMenu
  ➕ Install packages (GO)
  📄 List packages (GO)
  🧹 Mod Tidy (GO)
```

### .NET Projects

```vim
" Multi-project solution
:UniPackageMenu
> Select project: WebApi.csproj (.NET 8)
> Type: Newtonsoft
> Search results (filtered for net8.0)...
> Select: Newtonsoft.Json
> Installs: dotnet add WebApi.csproj package Newtonsoft.Json

" Direct install
:UniPackageInstall
> Select project: Domain.csproj (.NET Standard 2.1)
> Enter: Newtonsoft.Json@13.0.3
```

## Performance Optimizations

UniPackage.nvim includes enterprise-level performance optimizations:

### ⚡ Key Optimizations

- **Async HTTP Requests**: No UI blocking during package searches
- **In-Memory Cache**: LRU cache with 10MB memory limit and 100 entry limit
- **JSON Size Limits**: 1MB max response size to prevent memory exhaustion
- **Module Caching**: Cached manager modules for faster loading
- **Loading Indicators**: Visual feedback during async operations

### 📊 Performance Metrics

| Operation | Before | After | Improvement |
|-----------|---------|-------|-------------|
| Package Search | 2-10s (blocking) | Instant UI | ⚡⚡⚡⚡⚡ |
| Cache Access | 50-200ms (disk) | 0.1-1ms (memory) | ⚡⚡⚡⚡ |
| Module Loading | Repeated require() | Cached modules | ⚡⚡⚡ |
| Memory Usage | Unlimited | 10MB max | ⚡⚡⚡⚡ |

### 🧪 Testing

Run performance tests:
```vim
:luafile test_optimizations.lua
```

## Language-Specific Features

### JavaScript/TypeScript

- **Package Search**: Search npm registry with fuzzy finding
- **Multi-Registry**: Supports npm, yarn, pnpm, and bun registries
- **Version Selection**: Use `@version` syntax or `@` for latest
- **Async Search**: Non-blocking package searches with loading indicators

### Go

- **Module Management**: Supports `go.mod` and `go.work`
- **Mod Tidy**: Integrated `go mod tidy` command
- **Version Check**: Requires Go 1.18+ for workspace support

### .NET

- **Solution Support**: Multi-project solution handling
- **Project Selection**: Select specific project for operations
- **Framework Filtering**: Packages filtered by TargetFramework
- **NuGet Search**: Search nuget.org with framework compatibility
- **Async Operations**: Non-blocking NuGet searches

## Configuration Examples

### Modern Priority (Default)

```lua
require("unipackage").setup({
    package_managers = { "bun", "go", "dotnet", "pnpm", "npm", "yarn" }
})
```

### Language-Specific Priority

```lua
require("unipackage").setup({
    -- Prioritize specific languages
    package_managers = { "dotnet", "go", "bun", "pnpm", "npm", "yarn" }
})
```

### Customize Search Batch Size

```lua
require("unipackage").setup({
    search_batch_size = 10  -- Show 10 items per batch (default: 20, max: 100)
})
```

### Disable Fallback

```lua
require("unipackage").setup({
    fallback_to_any = false  -- Only work when lock file detected
})
```

### Runtime Configuration

```vim
" Change priority on the fly
:UniPackageSetup {"package_managers": ["bun", "npm"]}
```

## Detection Logic

UniPackage uses intelligent language detection:

1. **Language Detection**: Based on project files (go.mod, .csproj, package.json)
2. **Manager Filtering**: Only considers managers for detected language
3. **Priority Ordering**: Applies user-defined priority within language
4. **Fallback**: Falls back to any available manager if configured

### Detection Priority

```
Detected: go.mod → Language: Go → Manager: go
Detected: .csproj → Language: dotnet → Manager: dotnet
Detected: package.json → Language: javascript → Managers: bun, pnpm, npm, yarn
```

## Search Functionality

### NPM Search

- **Trigger**: Type package name without `@`
- **Registry**: Uses manager's configured registry
- **Results**: Name, version, downloads, description
- **Lazy Loading**: Configurable batch size (default: 20, max: 100)
- **Navigation**: ⬅️ Previous batch / 📥 Load more...
- **Filter**: Sorted by popularity
- **Cache**: 30 minutes

### NuGet Search

- **Trigger**: Type package ID without version
- **Registry**: nuget.org (with service index discovery)
- **Framework Filter**: Based on project's TargetFramework
- **Results**: Package ID, version, downloads, description
- **Cache**: 30 minutes per framework

## Troubleshooting

### "No supported package manager detected"

**Cause**: No project files found (go.mod, .csproj, package.json, etc.)
**Solution**: Ensure you're in a project directory with appropriate files

### "Package manager not available"

**Cause**: Required tool not installed (dotnet, go, npm, etc.)
**Solution**: Install the package manager:
```bash
# .NET
wget https://dot.net/v1/dotnet-install.sh | bash

# Go
# Download from https://go.dev/dl/

# Node.js package managers
npm install -g pnpm
npm install -g bun
```

### "Failed to execute search request"

**Cause**: Network issue or API unavailable
**Solution**: Check internet connection; cached results will be used if available

### Project not detected in .NET solution

**Cause**: No .sln or .csproj files found
**Solution**: Ensure you're in the solution root directory

### Debug Information

```vim
:UniPackageDebug
```

Shows:
- Current directory
- Detected language
- Detected managers
- Preferred manager
- Lock file status
- Cache statistics

### Health Check

```vim
:checkhealth unipackage
```

Verifies:
- Neovim version compatibility
- Required dependencies (toggleterm, curl)
- Available package managers
- Project detection status
- Configuration settings
- Cache statistics

### Clear Cache

```vim
:UniPackageClearCache
```

Clears all caches (memory cache, module cache, detection cache).

## Requirements

- Neovim >= 0.7.0
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) (for terminal integration)
- Language-specific tools:
  - **JavaScript**: npm, yarn, pnpm, or bun
  - **Go**: Go 1.18+ (for workspace support)
  - **.NET**: .NET SDK

## Contributing

Contributions are welcome! Please ensure:
1. Code follows existing patterns
2. All language managers are updated if changing core functionality
3. Documentation is updated
4. Test your changes with multiple package managers

## License

MIT License - see LICENSE file for details.

## Developer Documentation

For technical documentation, architecture details, and contribution guidelines, see [DEVELOPER.md](DEVELOPER.md).

## Acknowledgments

- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) - Terminal integration
- [NuGet API](https://docs.microsoft.com/en-us/nuget/api/) - .NET package search
- [npm Registry](https://github.com/npm/registry) - JavaScript package search

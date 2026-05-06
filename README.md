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
- 🍭 **Snacks Picker**: Optional integration with snacks.nvim for enhanced UI
- 💾 **Intelligent Caching**: In-memory LRU cache with size limits and persistence
- 🏷️ **Version Selection**: Select specific package versions (major → specific) with per-language configuration

## Supported Package Managers

| Language | Managers | Detection Files |
|----------|----------|----------------|
| JavaScript/TypeScript | bun, pnpm, npm, yarn | `package.json`, lock files |
| Go | go | `go.mod`, `go.sum`, `go.work` |
| .NET | dotnet | `.sln`, `.slnx`, `.csproj`, `.fsproj`, `.vbproj` |

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "sheymor/unipackage.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",     -- Required for async HTTP operations
        "folke/snacks.nvim",         -- Optional: for enhanced picker UI
    },
    config = function()
        require("unipackage").setup()
    end,
}

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "sheymor/unipackage.nvim",
    requires = { 
        "nvim-lua/plenary.nvim",
    },
    config = function()
        require("unipackage").setup()
    end,
}

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'sheymor/unipackage.nvim'
```

```lua
-- In your init.lua
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

    -- Picker UI configuration
    picker = "auto",          -- "auto", "native", or "snacks"
                              -- "auto" = use snacks.nvim if available, otherwise native
                              -- "native" = always use vim.ui.select/input
                              -- "snacks" = always use snacks.nvim (requires snacks.nvim)

    -- Version selection configuration
    version_selection = {
        enabled = false,                    -- Enable version selection (disabled by default)
        languages = {                       -- Per-language control
            javascript = true,              -- Enable for JavaScript/TypeScript
            dotnet = true,                  -- Enable for .NET
            go = false,                     -- Disabled for Go (uses go.mod)
        },
        include_prerelease = false,         -- Include pre-release versions (alpha, beta, rc)
        max_versions_shown = 20,            -- Maximum versions to show in expanded view
    }
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
| `:UniPackageNugetConfig` | Show NuGet configuration status |
| `:UniPackageClearCache` | Clear all caches |
| `:UniPackageNugetDebugSearch` | Debug NuGet search functionality |
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
> With version_selection enabled:
>   Select major version: 18.x (Latest: 18.2.0, 45 versions)
>   Select specific version: 18.1.0
>   Installs: npm install react@18.1.0
> Without version_selection:
>   Installs: npm install react@latest

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
> With version_selection enabled:
>   Select major version: 13.x (Latest: 13.0.3, 12 versions)
>   Select specific version: 13.0.1
>   Installs: dotnet add WebApi.csproj package Newtonsoft.Json --version 13.0.1
> Without version_selection:
>   Installs: dotnet add WebApi.csproj package Newtonsoft.Json

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

- **Solution Support**: Multi-project solution handling (`.sln` and `.slnx`)
- **Project Selection**: Select specific project for operations
- **Framework Filtering**: Packages filtered by TargetFramework
- **NuGet Search**: Search nuget.org with framework compatibility
- **Custom Package Sources**: Full support for `nuget.config` custom feeds
- **Environment Credentials**: Secure authentication via environment variables
- **Async Operations**: Non-blocking NuGet searches

## Configuration Examples

### Modern Priority (Default)

```lua
require("unipackage").setup({
    package_managers = { "bun", "go", "dotnet", "pnpm", "npm", "yarn" }
})
```

### Enable Version Selection

```lua
require("unipackage").setup({
    version_selection = {
        enabled = true,
        languages = {
            javascript = true,  -- Enable for JS/TS
            dotnet = true,      -- Enable for .NET
            go = false,         -- Keep disabled for Go
        },
        include_prerelease = false,  -- Exclude alpha/beta/rc versions
        max_versions_shown = 20,     -- Show up to 20 versions per major
    }
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

### Use Snacks Picker (Enhanced UI)

```lua
require("unipackage").setup({
    picker = "snacks"  -- Use snacks.nvim for all UI (requires folke/snacks.nvim)
})
```

With `picker = "auto"` (default), UniPackage will automatically use snacks.nvim if it's available in your runtimepath, otherwise it falls back to native `vim.ui.select`/`vim.ui.input`.

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

### Custom NuGet Sources

UniPackage automatically reads `nuget.config` to support custom package sources (Azure Artifacts, private feeds, etc.):

**Example nuget.config:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear/>
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="MyFeed" value="https://pkgs.dev.azure.com/org/_packaging/feed/nuget/v3/index.json" />
  </packageSources>
</configuration>
```

**Features:**
- Automatic discovery of `nuget.config` in project and parent directories
- Support for multiple package sources
- Results merged and sorted by popularity
- Source name displayed in search results for non-nuget.org feeds

### Azure DevOps Authentication (Recommended)

For Azure DevOps feeds, the **Azure Artifacts Credential Provider** is the recommended approach. It automatically handles authentication using your Azure CLI login session.

**1. Install Azure Artifacts Credential Provider:**
```bash
# Install the credential provider
curl -fsSL https://aka.ms/install-artifacts-credprovider.sh | bash

# Or on Windows PowerShell:
# iex "& { $(irm https://aka.ms/install-artifacts-credprovider.ps1) }"
```

**2. Log into Azure:**
```bash
az login
```

**3. Configure your nuget.config** (no credentials needed):
```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear/>
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="MyAzureFeed" value="https://pkgs.dev.azure.com/your-org/_packaging/your-feed/nuget/v3/index.json" />
  </packageSources>
</configuration>
```

**The plugin will automatically detect and use the credential provider for Azure DevOps feeds!**

### Secure Authentication (Alternative)

If you prefer not to use the credential provider, you can use environment variables:

**Environment Variable Format:**
```bash
UNIPACKAGE_NUGET_<SOURCE_NAME>_USERNAME=<username>
UNIPACKAGE_NUGET_<SOURCE_NAME>_TOKEN=<token>
```

**Example:**
```bash
# For a source named "MyFeed" in nuget.config
export UNIPACKAGE_NUGET_MYFEED_USERNAME="PAT"
export UNIPACKAGE_NUGET_MYFEED_TOKEN="your-azure-devops-pat"
```

**Authentication Priority:**
1. Environment variables (highest priority)
2. Azure Artifacts Credential Provider (for Azure DevOps feeds)
3. nuget.config file credentials (lowest priority)

### Verifying NuGet Configuration

To verify that your `nuget.config` and credentials are loaded correctly, use:

```vim
:UniPackageNugetConfig
```

This will display:
- ✓ Whether the config file was found and its location
- List of configured package sources with their URLs
- 🔐 Authentication status for each source:
  - `🔐 (env)` = Credentials loaded from environment variables
  - `🔐 (azure)` = Credentials from Azure Artifacts Credential Provider
  - `🔐 (config)` = Credentials loaded from `nuget.config` file
- Azure Credential Provider installation status
- Status of environment variables (✓ if set, ✗ if missing)

Press `q` or `<Esc>` to close the status window.

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
- Required dependencies (plenary.nvim, curl)
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
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (for async HTTP operations)
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

- [NuGet API](https://docs.microsoft.com/en-us/nuget/api/) - .NET package search
- [npm Registry](https://github.com/npm/registry) - JavaScript package search

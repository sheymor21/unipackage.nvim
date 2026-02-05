# Installation Guide

## Quick Install with lazy.nvim

Add to your `lua/plugins/unipackage.lua`:

```lua
return {
  "sheymor/unipackage.nvim",
  dependencies = {
    "akinsho/toggleterm.nvim",
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("unipackage").setup()
  end,
}
```

Or inline in your `init.lua`:

```lua
require("lazy").setup({
  {
    "sheymor/unipackage.nvim",
    dependencies = { 
      "akinsho/toggleterm.nvim",
      "nvim-lua/plenary.nvim",
    },
    config = true, -- Uses default setup
  },
})
```

## With Keymaps

```lua
{
  "sheymor/unipackage.nvim",
  dependencies = { 
    "akinsho/toggleterm.nvim",
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("unipackage").setup()
    
    -- Keymaps
    vim.keymap.set("n", "<leader>pm", "<cmd>UniPackageMenu<cr>", { desc = "Package Menu" })
    vim.keymap.set("n", "<leader>pi", "<cmd>UniPackageInstall<cr>", { desc = "Install Package" })
    vim.keymap.set("n", "<leader>pu", "<cmd>UniPackageUninstall<cr>", { desc = "Uninstall Package" })
    vim.keymap.set("n", "<leader>pl", "<cmd>UniPackageList<cr>", { desc = "List Packages" })
  end,
}
```

## With Custom Configuration

```lua
{
  "sheymor/unipackage.nvim",
  dependencies = { 
    "akinsho/toggleterm.nvim",
    "nvim-lua/plenary.nvim",
  },
  opts = {
    package_managers = { "bun", "go", "dotnet", "pnpm", "npm", "yarn" },
    fallback_to_any = true,
    warn_on_fallback = true,
  },
  config = function(_, opts)
    require("unipackage").setup(opts)
  end,
}
```

## Alternative Package Managers

### packer.nvim

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

### vim-plug

```vim
Plug 'akinsho/toggleterm.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'sheymor/unipackage.nvim'
```

```lua
-- In your init.lua
require("unipackage").setup()
```

## Requirements Check

After installation, verify everything works:

```vim
:UniPackageDebug
```

This will show:
- Detected language
- Available package managers
- Configuration status

## Troubleshooting

### Plugin not loading

1. Ensure `toggleterm.nvim` and `plenary.nvim` are installed
2. Check `:checkhealth lazy` for errors
3. Verify plugin is in lazy lock file: `:Lazy show`

### Commands not available

The commands are created when the plugin loads. If not available:
```lua
-- Force load
require("unipackage").setup()
```

### Package manager not detected

1. Verify you're in a project directory
2. Check project files exist (go.mod, .csproj, package.json)
3. Run `:UniPackageDebug` to see detection info

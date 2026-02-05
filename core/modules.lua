local M = {}

-- Core modules (always loaded)
local config = require("unipackage.core.config")
local utils = require("unipackage.core.utils")
local actions = require("unipackage.core.actions")
local ui = require("unipackage.core.ui")

-- Lazy loading system
M.lazy_load = function()
    return {
        config = config,
        utils = utils,
        actions = actions,
        ui = ui
    }
end

-- Setup function with ecosystem detection
M.setup = function(user_config)
    return config.setup(user_config)
end

-- Module accessor for backward compatibility
M.get_module = function(manager, language)
    local module_path = string.format("unipackage.%s.%s", language, manager)
    local ok, module = pcall(require, module_path)
    return ok and module or nil
end

-- Backward compatibility layer
M.get_legacy_module = function(manager)
    local ok, module = pcall(require, "unipackage." .. manager)
    return ok and module or nil
end

return M
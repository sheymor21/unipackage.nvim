local M = {}

--- Centralized error handling for UniPackage
-- @param context string: Context where error occurred (e.g., "install", "search")
-- @param message string: Error message
-- @param level number|nil: vim.log.levels value (default: ERROR)
-- @param silent boolean|nil: If true, don't show notification
function M.handle(context, message, level, silent)
    level = level or vim.log.levels.ERROR

    local formatted = string.format("UniPackage [%s]: %s", context, message)

    if not silent then
        vim.notify(formatted, level)
    end

    return formatted
end

--- Handle errors with return value
-- @param context string: Context where error occurred
-- @param message string: Error message
-- @param level number|nil: vim.log.levels value
-- @return nil, string: Returns nil and formatted error for function returns
function M.wrap(context, message, level)
    local err = M.handle(context, message, level)
    return nil, err
end

--- Validate that a value is not nil
-- @param value any: Value to check
-- @param name string: Name of the value for error message
-- @param context string: Context for error handling
-- @return boolean: true if valid
function M.assert_not_nil(value, name, context)
    if value == nil then
        M.handle(context, string.format("%s is required", name))
        return false
    end
    return true
end

--- Validate that a table is not empty
-- @param tbl table: Table to check
-- @param name string: Name of the table for error message
-- @param context string: Context for error handling
-- @return boolean: true if valid
function M.assert_not_empty(tbl, name, context)
    if type(tbl) ~= "table" or #tbl == 0 then
        M.handle(context, string.format("%s cannot be empty", name))
        return false
    end
    return true
end

return M

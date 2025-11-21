-- lua/UNX/provider/core.lua (元 UNX/provider.lua)

local explorer = require("UNX.ui.explorer")
local M = {}

-- capability: "unx.open"
-- UNL.api.provider.request("unx.open") から呼び出される
function M.open(opts)
    opts = opts or {}
    return explorer.open()
end

-- capability: "unx.is_open"
-- UNL.api.provider.request("unx.is_open") から呼び出される
function M.is_open(opts)
    opts = opts or {}
    return explorer.is_open()
end

-- 汎用リクエストハンドラ (init.lua が impl として登録する)
function M.request(opts)
    if opts and opts.capability == "unx.open" then
        return M.open(opts)
    elseif opts and opts.capability == "unx.is_open" then
        return M.is_open(opts)
    end
    return nil
end

return M

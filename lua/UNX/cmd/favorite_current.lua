-- lua/UNX/cmd/favorite_current.lua
local favorites_cache = require("UNX.cache.favorites")

local M = {}

function M.execute()
    local buf = vim.api.nvim_get_current_buf()
    local path = vim.api.nvim_buf_get_name(buf)
    
    if not path or path == "" then
        vim.notify("[UNX] Cannot add this buffer (no name) to Favorites.", vim.log.levels.WARN)
        return
    end
    
    -- ファイルの実在チェック（保存前のバッファなどは除外）
    if vim.fn.filereadable(path) == 0 then
         vim.notify("[UNX] File does not exist on disk. Please save it first.", vim.log.levels.WARN)
         return
    end

    -- トグル実行
    local added, msg = favorites_cache.toggle(path)
    local icon = added and "★ " or "☆ "
    
    vim.notify(string.format("[UNX] %s%s: %s", icon, msg, vim.fn.fnamemodify(path, ":t")), vim.log.levels.INFO)
    
    -- Explorerが開いていれば更新して即座に反映させる
    local ok_exp, explorer = pcall(require, "UNX.ui.explorer")
    if ok_exp and explorer.is_open() then
        explorer.refresh()
    end
end

return M

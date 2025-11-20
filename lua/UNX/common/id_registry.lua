-- lua/UNX/common/id_registry.lua
local M = {}
M.__index = M

function M.new()
    return setmetatable({ seen = {} }, M)
end

-- ノードIDの絶対的な一意性を保証する
-- base_key が重複した場合、_dup1, _dup2... を付与して空いているIDを探す
function M:get(base_key)
    local candidate = base_key
    local count = 1
    
    -- 候補がすでに登録済みであれば、接尾辞を変えて再試行
    while self.seen[candidate] do
        candidate = string.format("%s_dup%d", base_key, count)
        count = count + 1
    end
    
    self.seen[candidate] = true
    return candidate
end

-- パスを正規化してハッシュ化（表記ゆれによるID重複/不一致を防止）
function M.get_file_hash(path)
    if not path then return "nofile" end
    -- Windows対応: 大文字小文字の違いやスラッシュの違いを吸収
    local norm = path:gsub("\\", "/"):lower()
    return vim.fn.sha256(norm):sub(1, 8)
end

return M

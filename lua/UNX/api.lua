-- lua/UNX/api.lua
local M = {}

-- 内部実装（UI）への依存
local Explorer = require("UNX.ui.explorer")

-- ======================================================
-- Explorer API
-- ======================================================

--- エクスプローラーを開く（既に開いている場合はフォーカスする）
function M.explorer_open()
    if not Explorer.is_open() then
        Explorer.open()
    else
        -- 既に開いているならメインウィンドウにフォーカス
        -- (ui/explorer.lua の内部状態にアクセスできないため、openを呼んでフォーカス処理に任せる)
        Explorer.open()
    end
end

--- エクスプローラーを閉じる
function M.explorer_close()
    if Explorer.is_open() then
        Explorer.close()
    end
end

--- 開閉トグル
function M.explorer_toggle()
    if Explorer.is_open() then
        Explorer.close()
    else
        Explorer.open()
    end
end

--- エクスプローラーの内容を更新（Gitステータスなど）
function M.explorer_refresh()
    if Explorer.is_open() then
        Explorer.refresh()
    end
end

return M

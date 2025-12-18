-- lua/UNX/api.lua
local M = {}

-- 内部実装（UI）への依存
local Explorer = require("UNX.ui.explorer")
local cmd_add_favorites = require("UNX.cmd.add_favorites")
local cmd_favorites_files = require("UNX.cmd.favorites_files")
local cmd_pending_files = require("UNX.cmd.pending_files")
local cmd_unpushed_files = require("UNX.cmd.unpushed_files")
local cmd_favorite_current = require("UNX.cmd.favorite_current")
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

function M.explorer_is_open()
  if Explorer.is_open() then
    return true
  end
  return false 
end

function M.add_favorites(opts)
  cmd_add_favorites.execute(opts)
end

function M.favorites_files(opts)
  cmd_favorites_files.execute(opts)
end

function M.pending_files(opts)
  cmd_pending_files.execute(opts)
end

function M.unpushed_files(opts)
  cmd_unpushed_files.execute(opts)
end

function M.favorite_current()
  cmd_favorite_current.execute()
end

return M

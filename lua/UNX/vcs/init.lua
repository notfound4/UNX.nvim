-- lua/UNX/vcs/init.lua
local M = {}

-- バックエンドの読み込み
local git = require("UNX.vcs.git")
-- 将来: local p4 = require("UNX.vcs.p4")

--- VCSの状態を更新する
--- @param root_path string プロジェクトルート
--- @param on_complete function 完了コールバック
function M.refresh(root_path, on_complete)
    -- 将来的にはここで P4 の refresh も並行して呼ぶなどの拡張が可能
    git.refresh(root_path, on_complete)
end

--- パスのVCSステータスを取得する
--- @param path string ファイルパス
--- @return string|nil ステータスコード
function M.get_status(path)
    -- 現状は Git のみを返す
    -- 将来的には: local s = git.get_status(path) or p4.get_status(path) のように合成可能
    return git.get_status(path)
end

--- キャッシュクリア
function M.clear()
    git.clear()
    -- p4.clear()
end

return M

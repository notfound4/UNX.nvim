-- lua/UNX/vcs/init.lua
local M = {}

local git = require("UNX.vcs.git")
local p4 = require("UNX.vcs.p4") -- ★追加

--- VCSの状態を更新する
function M.refresh(root_path, on_complete)
    -- 並列で実行し、両方終わったら完了とする
    local pending = 2
    local function check_done()
        pending = pending - 1
        if pending <= 0 and on_complete then
            on_complete()
        end
    end

    git.refresh(root_path, check_done)
    p4.refresh(root_path, check_done)
end

--- パスのVCSステータスを取得する
function M.get_status(path)
    -- P4のステータスを優先 (Unrealプロジェクトは通常P4管理)
    local p4_stat = p4.get_status(path)
    if p4_stat then
        return p4_stat
    end
    
    -- P4になければGitを見る (PluginsフォルダだけGit管理、のようなケース対応)
    return git.get_status(path)
end

--- 自動チェックアウトなどのためにP4操作を公開
function M.p4_edit(path)
    return p4.edit(path)
end

function M.p4_revert(path)
    return p4.revert(path)
end

function M.clear()
    git.clear()
    p4.clear()
end

function M.is_p4_managed(path)
    return p4.is_managed(path)
end
return M

local M = {}

local git = require("UNX.vcs.git")
local p4 = require("UNX.vcs.p4")

--- 設定を取得するヘルパー
local function get_config()
    -- UNL経由で設定を取得 (defaults + user + .unlrc.json)
    local conf = require("UNL.config").get("UNX")
    local vcs = conf.vcs or {}
    
    return {
        git = vcs.git and vcs.git.enabled ~= false, -- デフォルトは true
        p4  = vcs.p4  and vcs.p4.enabled  ~= false, -- デフォルトは true
    }
end

--- VCSの状態を更新する
function M.refresh(root_path, on_complete)
    local enabled = get_config()
    
    -- 実行すべきタスクの数をカウント
    local pending = 0
    if enabled.git then pending = pending + 1 end
    if enabled.p4  then pending = pending + 1 end

    -- 何も有効でなければ即終了
    if pending == 0 then
        if on_complete then on_complete() end
        return
    end

    local function check_done()
        pending = pending - 1
        if pending <= 0 and on_complete then
            on_complete()
        end
    end

    -- 設定で有効な場合のみ refresh を実行
    if enabled.git then
        git.refresh(root_path, check_done)
    end

    if enabled.p4 then
        p4.refresh(root_path, check_done)
    end
end

--- パスのVCSステータスを取得する
function M.get_status(path)
    local enabled = get_config()

    -- P4が有効なら優先してチェック
    if enabled.p4 then
        local p4_stat = p4.get_status(path)
        if p4_stat then
            return p4_stat
        end
    end
    
    -- P4で見つからない、かつGitが有効ならチェック
    if enabled.git then
        return git.get_status(path)
    end

    return nil
end

--- P4管理下かどうかチェック
function M.is_p4_managed(path)
    -- ここでも設定を見るべきですが、
    -- 通常この関数を呼ぶ側(init.lua)ですでにenabledチェックをしていることが多いです。
    -- 念のためここでもチェックを入れると堅牢です。
    local enabled = get_config()
    if not enabled.p4 then return false end
    
    return p4.is_managed(path)
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

return M

-- lua/UNX/vcs/init.lua
local M = {}

-- VCSプロバイダーの定義 (優先順位順: P4 -> Git)
-- 新しいVCSを追加する場合はここに追記するだけで済みます
local providers = {
    { name = "p4",  module = require("UNX.vcs.p4") },
    { name = "git", module = require("UNX.vcs.git") },
}

--- 設定を取得するヘルパー
local function get_config()
    -- UNL経由で設定を取得 (defaults + user + .unlrc.json)
    local conf = require("UNL.config").get("UNX")
    return conf.vcs or {}
end

--- VCSの状態を更新する
function M.refresh(root_path, on_complete)
    local conf = get_config()
    local pending = 0

    -- 1. 実行すべきタスク数をカウント
    for _, provider in ipairs(providers) do
        local cfg = conf[provider.name]
        if cfg and cfg.enabled ~= false then
            pending = pending + 1
        end
    end

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

    -- 2. 各プロバイダーの refresh を実行
    for _, provider in ipairs(providers) do
        local cfg = conf[provider.name]
        if cfg and cfg.enabled ~= false then
            provider.module.refresh(root_path, check_done)
        end
    end
end

--- 全てのVCS変更ファイルをマージして返す
function M.get_aggregated_changes()
    local conf = get_config()
    local combined = {}
    local seen = {}

    for _, provider in ipairs(providers) do
        local cfg = conf[provider.name]
        -- 有効かつ、インターフェイス(get_changes)を実装しているか確認
        if cfg and cfg.enabled ~= false and type(provider.module.get_changes) == "function" then
            local changes = provider.module.get_changes()
            
            for _, item in ipairs(changes) do
                if not seen[item.path] then
                    seen[item.path] = true
                    -- どのVCS由来かの情報を付与したい場合はここで item.source = provider.name
                    table.insert(combined, item)
                end
            end
        end
    end
    
    -- パス順にソートしてUIでの表示を安定させる
    table.sort(combined, function(a, b) return a.path < b.path end)
    return combined
end

--- パスのVCSステータスを取得する
function M.get_status(path)
    local conf = get_config()

    -- 優先順位順(P4 -> Git)にステータスを確認し、最初に見つかったものを返す
    for _, provider in ipairs(providers) do
        local cfg = conf[provider.name]
        if cfg and cfg.enabled ~= false then
            local status = provider.module.get_status(path)
            if status then
                return status
            end
        end
    end

    return nil
end

--- 全プロバイダーのキャッシュをクリア
function M.clear()
    for _, provider in ipairs(providers) do
        if type(provider.module.clear) == "function" then
            provider.module.clear()
        end
    end
end

-- ======================================================
-- P4 Specific Helpers (Auto Checkout用)
-- ======================================================

-- P4プロバイダーを直接取得するヘルパー
local function get_p4_module()
    for _, p in ipairs(providers) do
        if p.name == "p4" then return p.module end
    end
    return nil
end

function M.is_p4_managed(path)
    local conf = get_config()
    if not conf.p4 or conf.p4.enabled == false then return false end
    
    local p4 = get_p4_module()
    return p4 and p4.is_managed(path) or false
end

function M.p4_edit(path)
    local p4 = get_p4_module()
    return p4 and p4.edit(path) or false
end

function M.p4_revert(path)
    local p4 = get_p4_module()
    return p4 and p4.revert(path) or false
end

return M

-- lua/UNX/vcs/init.lua
local M = {}

-- VCSプロバイダーの定義 (優先順位順: P4 -> Git)
local providers = {
    { name = "p4",  module = require("UNX.vcs.p4") },
    { name = "git", module = require("UNX.vcs.git") },
}

--- 設定を取得するヘルパー
local function get_config()
    local conf = require("UNL.config").get("UNX")
    return conf.vcs or {}
end

--- VCSの状態を更新する
function M.refresh(root_path, on_complete)
    local conf = get_config()
    local pending = 0

    for _, provider in ipairs(providers) do
        local cfg = conf[provider.name]
        if cfg and cfg.enabled ~= false then
            pending = pending + 1
        end
    end

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

    for _, provider in ipairs(providers) do
        local cfg = conf[provider.name]
        if cfg and cfg.enabled ~= false then
            provider.module.refresh(root_path, check_done)
        end
    end
end

--- 全てのVCS変更ファイルをマージして返す (Local Changes)
function M.get_aggregated_changes()
    local conf = get_config()
    local combined = {}
    local seen = {}

    for _, provider in ipairs(providers) do
        local cfg = conf[provider.name]
        if cfg and cfg.enabled ~= false and type(provider.module.get_changes) == "function" then
            local changes = provider.module.get_changes()
            
            for _, item in ipairs(changes) do
                if not seen[item.path] then
                    seen[item.path] = true
                    table.insert(combined, item)
                end
            end
        end
    end
    
    table.sort(combined, function(a, b) return a.path < b.path end)
    return combined
end

-- ★★★ 追加: 全ての未プッシュファイルをマージして返す (Remote Diff) ★★★
function M.get_aggregated_unpushed()
    local conf = get_config()
    local combined = {}
    local seen = {}

    for _, provider in ipairs(providers) do
        local cfg = conf[provider.name]
        -- get_unpushed を実装しているプロバイダーのみ (現在はGitのみ)
        if cfg and cfg.enabled ~= false and type(provider.module.get_unpushed) == "function" then
            local changes = provider.module.get_unpushed()
            
            for _, item in ipairs(changes) do
                if not seen[item.path] then
                    seen[item.path] = true
                    table.insert(combined, item)
                end
            end
        end
    end
    
    table.sort(combined, function(a, b) return a.path < b.path end)
    return combined
end
-- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★

--- パスのVCSステータスを取得する
function M.get_status(path)
    local conf = get_config()

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

-- P4 Helpers
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

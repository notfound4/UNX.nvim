-- lua/UNX/vcs/init.lua
local M = {}
local unl_vcs = require("UNL.vcs")

-- VCSプロバイダーの定義 (UNL.vcs の各モジュールを直接参照)
local providers = {
    { name = "p4",  module = require("UNL.vcs.p4") },
    { name = "git", module = require("UNL.vcs.git") },
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

--- 全ての未プッシュファイルをマージして返す (Remote Diff)
function M.get_aggregated_unpushed()
    local conf = get_config()
    local combined = {}
    local seen = {}

    for _, provider in ipairs(providers) do
        local cfg = conf[provider.name]
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
    unl_vcs.clear()
end

function M.is_p4_managed(path)
    local conf = get_config()
    if not conf.p4 or conf.p4.enabled == false then return false end
    return unl_vcs.is_p4_managed(path)
end

function M.p4_edit(path)
    return unl_vcs.p4_edit(path)
end

function M.p4_revert(path)
    return unl_vcs.p4_revert(path)
end

function M.get_file_content(path, on_success)
    local conf = get_config()
    local index = 1
    
    local function try_next()
        if index > #providers then
            on_success(nil)
            return
        end
        
        local provider = providers[index]
        index = index + 1
        local cfg = conf[provider.name]
        
        if cfg and cfg.enabled ~= false and type(provider.module.get_file_content) == "function" then
            provider.module.get_file_content(path, function(content)
                if content then
                    on_success(content)
                else
                    try_next()
                end
            end)
        else
            try_next()
        end
    end
    
    try_next()
end

return M
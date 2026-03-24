-- lua/UNX/context/uproject.lua
local M = {}

local unl_context
-- UNL.context内でデータを区別するための識別子
local NS = "UNX"
local GROUP_KEY = "view_uproject"
local DATA_KEY = "state"

local default_state = {
    mode = "normal", -- "uep" | "none" | "normal"
    project_root = nil, -- "C:/Work/MyProject"
    engine_root = nil, -- "C:/UE_5.3/Engine"
    is_pending_expanded = true,
    is_favorites_expanded = true,
    filter_text = "", -- ★追加: フィルタリング用テキスト
    config_filter_text = "", -- ★追加: Configフィルタリング用テキスト
}

local function get_store_handle()
    -- 1. 安全に require (UNLがロードされていない場合の対策)
    if not unl_context then
        local ok, mod = pcall(require, "UNL.context")
        if ok then
            unl_context = mod
        else
            return nil
        end
    end

    -- 2. 正しい階層でハンドラを取得: use(NS) -> key(GROUP)
    -- ここが以前のエラーの原因（keyを挟んでいなかった）の修正点です
    return unl_context.use(NS):key(GROUP_KEY)
end

function M.get()
    local handle = get_store_handle()

    -- ハンドル取得失敗、またはAPI不整合時のガード
    if not handle or type(handle.get) ~= "function" then
        return vim.deepcopy(default_state)
    end

    local data = handle:get(DATA_KEY)
    if not data then
        data = vim.deepcopy(default_state)
        -- 初期値を保存しておく
        handle:set(DATA_KEY, data)
    end

    -- Ensure defaults
    if data.is_pending_expanded == nil then data.is_pending_expanded = true end
    if data.pending_states == nil then data.pending_states = {} end
    if data.config_filter_text == nil then data.config_filter_text = "" end
    
    return data
end

function M.set(data)
    local handle = get_store_handle()
    if handle and type(handle.set) == "function" then
        -- 必要なデータフィールドだけを保存する（念の為のフィルタリング）
        local clean_data = {
            mode = data.mode,
            project_root = data.project_root,
            engine_root = data.engine_root,
            is_pending_expanded = data.is_pending_expanded,
            is_favorites_expanded = data.is_favorites_expanded,
            filter_text = data.filter_text,
            config_filter_text = data.config_filter_text or "",
            pending_states = data.pending_states or {}, -- 確実に保存
        }

        handle:set(DATA_KEY, clean_data)
    end
end

return M

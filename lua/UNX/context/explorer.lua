-- lua/UNX/context/explorer.lua
local M = {}

local unl_context
local KEY = "explorer_state"

local default_state = {
    buf_uproject = nil,
    buf_symbols = nil,
    buf_insights = nil,
    win_main = nil,
    win_sub = nil,
    current_tab = "uproject",
    uproject_tree = nil,
    class_func_tree = nil,
    insights_tree = nil,
}

-- ★追加: メモリ内キャッシュ (UNLが読み込めない/失敗したときの保険)
local internal_state = vim.deepcopy(default_state)

local function get_handle()
    if not unl_context then
        local ok, mod = pcall(require, "UNL.context")
        if ok then
            unl_context = mod
        else
            return nil
        end
    end
    return unl_context.use("UNX")
end

function M.get()
    local handle = get_handle()

    -- ハンドルが有効なら UNL から最新を取得してキャッシュを更新
    if handle and type(handle.get) == "function" then
        local remote_data = handle:get(KEY)
        if remote_data then
            internal_state = remote_data
        end
    end

    -- キャッシュを返す (これで set した直後は確実にその値が返る)
    return internal_state
end

function M.set(state)
    -- ★重要: まずメモリ内キャッシュを更新
    internal_state = state

    -- その後、可能なら UNL にも保存 (永続化)
    local handle = get_handle()
    if handle and type(handle.set) == "function" then
        handle:set(KEY, state)
    end
end

return M

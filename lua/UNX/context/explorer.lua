-- lua/UNX/context/explorer.lua
local M = {}

local unl_context
local KEY = "explorer_state"

-- ui/explorer.lua にあった local state の初期値をここに移動
local default_state = {
    -- バッファID
    buf_uproject = nil,
    buf_symbols = nil,
    buf_insights = nil,

    -- ウィンドウID
    win_main = nil,
    win_sub = nil,

    -- 現在のモード
    current_tab = "uproject",

    -- Treeインスタンス
    uproject_tree = nil,
    class_func_tree = nil,
    insights_tree = nil,
}

local function get_handle()
    -- 安全に require する
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

    -- handleが取得できない、またはメソッドがない場合はデフォルトを返す (クラッシュ防止)
    if not handle or type(handle.get) ~= "function" then
        return vim.deepcopy(default_state)
    end

    local state = handle:get(KEY)
    if not state then
        state = vim.deepcopy(default_state)
        handle:set(KEY, state)
    end
    return state
end

function M.set(state)
    local handle = get_handle()
    -- handleが有効な場合のみ保存する
    if handle and type(handle.set) == "function" then
        handle:set(KEY, state)
    end
end

return M

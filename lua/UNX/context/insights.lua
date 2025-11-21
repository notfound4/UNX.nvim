-- lua/UNX/context/insights.lua
local M = {}

local unl_context
local NS = "UNX"
local GROUP_KEY = "view_insights"
local DATA_KEY = "state"

local default_state = {
    -- トレースデータの識別子や基本情報のみを保存
    -- 巨大な frame_events ツリーそのものは保存しません (サイズ過大になるため)
    -- 必要であれば再取得する設計にします。
    trace_handle_id = nil,
    frame_number = nil,
    frame_summary = nil, -- { duration_ms, start_time, etc. }
}

local function get_store_handle()
    if not unl_context then
        local ok, mod = pcall(require, "UNL.context")
        if ok then
            unl_context = mod
        else
            return nil
        end
    end
    return unl_context.use(NS):key(GROUP_KEY)
end

function M.get()
    local handle = get_store_handle()
    if not handle or type(handle.get) ~= "function" then
        return vim.deepcopy(default_state)
    end

    local data = handle:get(DATA_KEY)
    if not data then
        data = vim.deepcopy(default_state)
        handle:set(DATA_KEY, data)
    end
    return data
end

function M.set(data)
    local handle = get_store_handle()
    if handle and type(handle.set) == "function" then
        -- 保存対象を絞り込む
        local clean_data = {
            trace_handle_id = data.trace_handle_id,
            frame_number = data.frame_number,
            frame_summary = data.frame_summary,
        }
        handle:set(DATA_KEY, clean_data)
    end
end

return M

-- lua/UNX/ui/view/insights.lua
local Tree = require("nui.tree")
local Line = require("nui.line")

local M = {}
local config = {}
local active_tree = nil -- Treeインスタンスを保持

-- 追記: 状態を保持するテーブル
local state = {
    trace_handle = nil,
    frame_data = nil,
    frame_events = nil,
    is_expanded = {} -- 展開状態を保持するマップ
}

local function prepare_node(node)
    local line = Line()
    line:append(string.rep("  ", node:get_depth() - 1))
    
    -- 子を持つかどうかは、Nui Treeのデータ構造に基づいて判定します。
    local has_children = node:has_children() or (node.children and #node.children > 0)
    
    local ui_config = config.insights_ui or {}
    local icon_config = ui_config.icon or {}
    
    local default_open = ""      -- 開いているフォルダ
    local default_closed = ""    -- 閉じているフォルダ
    local default_group_hl = "UNXDirectoryIcon"
    local default_leaf_icon = "󰊕"
    local default_leaf_hl = "Function"
    
    local icon = default_leaf_icon
    local icon_hl = default_leaf_hl
    local text_hl = default_leaf_hl

    if node.kind == "Frame" then
        -- FrameノードはTrace Rootなので特別扱い
        icon = "󰔐"
        icon_hl = "Title"
        text_hl = "Title"
    elseif has_children then
        -- 子を持つノード（フォルダアイコン）
        icon_hl = icon_config.group_icon_hl or default_group_hl
        text_hl = icon_hl
        
        if node:is_expanded() then
            -- 開いている状態
            icon = icon_config.group_icon_open or default_open
        else
            -- 閉じている状態
            icon = icon_config.group_icon_closed or default_closed
        end
    else
        -- 子を持たないノード（関数アイコン）
        icon = icon_config.leaf_icon or default_leaf_icon
        icon_hl = icon_config.leaf_icon_hl or default_leaf_hl
        text_hl = icon_hl
    end
    -- ★★★ 修正箇所ここまで ★★★
    
    -- 描画ロジック
    line:append(icon .. " ", icon_hl)
    line:append(node.text, text_hl)

    if node.detail then
        line:append(" (" .. node.detail .. ")", "Comment")
    end

    return line
end

-- 追記: ULGのイベントツリーをNui Treeノードに再帰的に変換
local function convert_events_to_nodes(events, parent_id)
    local nodes = {}
    
    for i, event in ipairs(events) do
        -- duration_ms がすでに存在するか、計算する
        local duration_ms = (event.e - event.s) * 1000
        local base_id = string.format("%s_ev%d", parent_id, i)

        local children_nodes = nil
        local has_children = event.children and #event.children > 0
        
        -- 再帰的に子ノードを処理
        if has_children then
            children_nodes = convert_events_to_nodes(event.children, base_id)
        end
        
        -- GameThreadのトップレベルイベントかどうかで Kind を判定
        local kind = "Stat"
        if event.name and event.name:match("::Tick") then kind = "Frame" end
        
        local node = Tree.Node({
            text = event.name or "Unknown Event",
            kind = kind,
            detail = string.format("%.3fms", duration_ms),
            id = base_id
        }, children_nodes)
        
        -- デフォルトの展開状態を決定（以前展開されていたら再展開）
        if has_children and state.is_expanded[base_id] then
             node:expand()
        end
        
        table.insert(nodes, node)
    end
    
    return nodes
end


function M.setup(user_config)
    config = user_config
end

function M.create(bufnr)
    -- ★修正: ダミーデータではなく空のツリーで初期化
    local tree = Tree({
        bufnr = bufnr,
        nodes = {}, 
        prepare_node = prepare_node,
    })
    active_tree = tree
    return tree
end

-- 追記: ULGからデータを受け取る関数
function M.set_data(trace_handle, frame_data)
    -- 状態を更新
    state.trace_handle = trace_handle
    state.frame_data = frame_data
    state.frame_events = frame_data.events_tree
    
    -- 再描画
    if active_tree then
        M.render(active_tree)
    end
end
-- ノードデータを使ってTreeを再描画する
function M.render(tree_instance)
    if tree_instance and state.frame_data and state.frame_events then
        local root_id = string.format("frame_%d", state.frame_data.frame_number)
        
        -- ULGイベントツリーをNui Treeノードに変換
        local nodes = convert_events_to_nodes(state.frame_events, root_id)
        
        -- フレーム情報を示すルートノードを作成
        local root_text = string.format("Frame %d: %.3fms", state.frame_data.frame_number, state.frame_data.duration_ms)
        local frame_node = Tree.Node({
            text = root_text,
            kind = "Frame",
            detail = string.format("Start: %.3fs", state.frame_data.frame_start_time),
            id = root_id
        }, nodes)
        
        -- ルートノードは常に展開
        frame_node:expand()
        
        tree_instance:set_nodes({ frame_node })
        tree_instance:render()
    end
end

-- ノードアクション（トグル）を定義
function M.on_node_action(tree_instance, split_instance, other_split_instance)
    local node = tree_instance:get_node()
    if not node then return end
    
    if node:has_children() then
        if node:is_expanded() then node:collapse() else node:expand() end
        
        -- 修正: 展開状態を保持
        state.is_expanded[node.id] = node:is_expanded()
        
        tree_instance:render()
    -- ★追記: Leafノードの場合、ソースコードへのジャンプを検討する
    elseif node.kind ~= "Frame" then
        -- (現時点では、Traceイベントにファイルパスや行番号が含まれていないため、ジャンプは実装しない)
        -- ただし、イベント名（node.text）からTimer情報を逆引きして、ソースにジャンプする拡張の余地がある
    end
end

return M

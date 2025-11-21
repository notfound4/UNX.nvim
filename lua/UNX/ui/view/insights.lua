-- lua/UNX/ui/view/insights.lua
local Tree = require("nui.tree")
local Line = require("nui.line")

local M = {}
local config = {}

local function prepare_node(node)
    local line = Line()
    line:append(string.rep("  ", node:get_depth() - 1))
    
    local icon = "⚡ "
    local icon_hl = "Special"
    local text_hl = "Normal"
    
    if node.kind == "Frame" then
        icon = "󰔐 "
        text_hl = "Title"
    elseif node.kind == "Stat" then
        icon = " "
        text_hl = "Identifier"
    end

    line:append(icon, icon_hl)
    line:append(node.text, text_hl)

    if node.detail then
        line:append(" (" .. node.detail .. ")", "Comment")
    end

    return line
end

function M.setup(user_config)
    config = user_config
end

function M.create(bufnr)
    -- ★空のTreeインスタンスを作成
    local dummy_nodes = {
        Tree.Node({
            text = "Insights: 1 Frame Data (Dummy)",
            kind = "Frame",
            detail = "3.4ms",
            id = "frame_001"
        }, {
            Tree.Node({ text = "Rendering", kind = "Stat", detail = "1.2ms", id = "stat_render" }),
            Tree.Node({ text = "Game Thread", kind = "Stat", detail = "1.8ms", id = "stat_game" }),
        })
    }
    
    return Tree({
        bufnr = bufnr,
        nodes = dummy_nodes, -- ダミーデータを設定
        prepare_node = prepare_node,
    })
end

-- ノードデータを使ってTreeを再描画する
function M.render(tree_instance)
    if tree_instance then
        tree_instance:render()
    end
end

-- 現時点では、ノードをクリックしてもトグル以外何もしないアクションを定義
function M.on_node_action(tree_instance, split_instance, other_split_instance)
    local node = tree_instance:get_node()
    if not node then return end
    
    if node:has_children() then
        if node:is_expanded() then node:collapse() else node:expand() end
        tree_instance:render()
    end
end

return M

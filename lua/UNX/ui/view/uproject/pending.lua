-- lua/UNX/ui/view/uproject/pending.lua

local Tree = require("nui.tree")
local unx_vcs = require("UNX.vcs")
local unl_path = require("UNL.path")

local M = {}

M.ROOT_TYPE = "pending_changes_root"

-- 子ノード生成関数 (順序の関係で先に定義するか、M.経由で呼ぶ)
function M.create_children_nodes()
    local changes = unx_vcs.get_aggregated_changes()
    local nodes = {}
    
    for _, item in ipairs(changes) do
        local name = vim.fn.fnamemodify(item.path, ":t")
        
        table.insert(nodes, Tree.Node({
            text = name,
            id = "pending_" .. unl_path.normalize(item.path),
            path = item.path,
            type = "file",
            _has_children = false,
            extra = {
                uep_type = "fs",
                is_pending_item = true
            }
        }))
    end
    
    return nodes
end

-- ★修正: 開いているなら、作成時に子ノードを埋め込む
function M.create_root_node(is_expanded)
    local changes = unx_vcs.get_aggregated_changes()
    
    if #changes == 0 then 
        return nil 
    end

    -- 開いている状態なら、ここで子ノードを生成してしまう
    local children = nil
    if is_expanded then
        children = M.create_children_nodes()
    end

    local node = Tree.Node({
        text = "Pending Changes",
        id = "root_pending_changes",
        type = "directory",
        _has_children = true,
        extra = {
            uep_type = M.ROOT_TYPE,
        }
    }, children) -- 第2引数に children を渡す
    
    if is_expanded then
        node:expand()
    else
        node:collapse()
    end
    
    return node
end

return M

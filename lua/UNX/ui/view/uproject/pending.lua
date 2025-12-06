-- lua/UNX/ui/view/uproject/pending.lua

local Tree = require("nui.tree")
local unx_vcs = require("UNX.vcs")
local unl_path = require("UNL.path")

local M = {}

M.ROOT_TYPE_PENDING = "pending_changes_root"
M.ROOT_TYPE_UNPUSHED = "unpushed_commits_root"

-- ★修正: id_prefix を受け取ってユニークなIDを作る
local function create_file_nodes(file_list, id_prefix, icon_override)
    local nodes = {}
    for _, item in ipairs(file_list) do
        local name = vim.fn.fnamemodify(item.path, ":t")
        -- IDを "pending_vcs_..." と "unpushed_vcs_..." に分ける
        local unique_id = string.format("%s_vcs_%s", id_prefix, unl_path.normalize(item.path))
        
        table.insert(nodes, Tree.Node({
            text = name,
            id = unique_id,
            path = item.path,
            type = "file",
            _has_children = false,
            extra = {
                uep_type = "fs",
                is_pending_item = true, 
                vcs_status_override = icon_override
            }
        }))
    end
    return nodes
end

-- 子ノード生成 (公開API)
function M.create_children_nodes(parent_node)
    local uep_type = parent_node.extra.uep_type
    
    if uep_type == M.ROOT_TYPE_PENDING then
        local changes = unx_vcs.get_aggregated_changes()
        -- ★修正: prefix "pending" を渡す
        return create_file_nodes(changes, "pending", nil)
        
    elseif uep_type == M.ROOT_TYPE_UNPUSHED then
        local unpushed = unx_vcs.get_aggregated_unpushed()
        -- ★修正: prefix "unpushed" を渡す
        return create_file_nodes(unpushed, "unpushed", "Unpushed") 
    end
    
    return {}
end

-- ルートノード群を作成して返す
function M.create_root_nodes(is_expanded_map)
    local nodes = {}
    is_expanded_map = is_expanded_map or {}

    -- 1. Pending Changes (Local)
    local changes = unx_vcs.get_aggregated_changes()
    if #changes > 0 then
        local is_exp = is_expanded_map[M.ROOT_TYPE_PENDING]
        if is_exp == nil then is_exp = true end

        local children = nil
        if is_exp then
            -- ★修正: prefix "pending"
            children = create_file_nodes(changes, "pending", nil)
        end

        local node = Tree.Node({
            text = "Pending Changes",
            id = "root_pending_changes",
            type = "directory",
            _has_children = true,
            extra = { uep_type = M.ROOT_TYPE_PENDING }
        }, children)
        
        if is_exp then node:expand() else node:collapse() end
        table.insert(nodes, node)
    end

    -- 2. Unpushed Commits (Remote)
    local unpushed = unx_vcs.get_aggregated_unpushed()
    if #unpushed > 0 then
        local is_exp = is_expanded_map[M.ROOT_TYPE_UNPUSHED]
        if is_exp == nil then is_exp = true end

        local children = nil
        if is_exp then
            -- ★修正: prefix "unpushed"
            children = create_file_nodes(unpushed, "unpushed", "Unpushed")
        end

        local node = Tree.Node({
            text = "Unpushed Commits",
            id = "root_unpushed_commits",
            type = "directory",
            _has_children = true,
            extra = { uep_type = M.ROOT_TYPE_UNPUSHED }
        }, children)

        if is_exp then node:expand() else node:collapse() end
        table.insert(nodes, node)
    end
    
    return nodes
end

return M

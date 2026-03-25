-- lua/UNX/ui/view/uproject/favorites.lua

local Tree = require("nui.tree")
local unl_path = require("UNL.path")
-- ★修正: UNX内部のキャッシュモジュールを使用
local favorites_cache = require("UNX.cache.favorites")

local M = {}

M.ROOT_TYPE = "favorites_root"

function M.create_children_nodes(project_root)
    local favorites = favorites_cache.load(project_root)
    
    local folder_defs = {}
    local items_by_folder = {}
    local direct_items = {}

    -- 1. データの整理
    for _, item in ipairs(favorites) do
        if item.is_folder then
            table.insert(folder_defs, item)
        else
            local f_name = item.folder or "Default"
            if f_name == "Default" then
                table.insert(direct_items, item)
            else
                if not items_by_folder[f_name] then items_by_folder[f_name] = {} end
                table.insert(items_by_folder[f_name], item)
            end
        end
    end

    -- 2. 再帰的にノードを構築する関数
    local function build_recursive(parent_name)
        local nodes = {}

        -- この親を持つフォルダを探して追加
        for _, f in ipairs(folder_defs) do
            if f.parent == parent_name then
                local f_children = build_recursive(f.name)
                
                table.insert(nodes, Tree.Node({
                    text = f.name,
                    id = "fav_folder_" .. f.name,
                    type = "directory",
                    _has_children = #f_children > 0,
                    extra = { uep_type = "fs", is_favorite_folder = true, project_root = project_root }
                }, f_children))
            end
        end

        -- このフォルダに属するアイテムを追加
        if parent_name and items_by_folder[parent_name] then
            for _, item in ipairs(items_by_folder[parent_name]) do
                local is_dir = vim.fn.isdirectory(item.path) == 1
                table.insert(nodes, Tree.Node({
                    text = item.name,
                    id = "fav_item_" .. unl_path.normalize(item.path),
                    path = item.path,
                    type = is_dir and "directory" or "file",
                    extra = { uep_type = "fs", is_favorite_item = true, project_root = project_root }
                }))
            end
        end

        -- ソート (フォルダ優先、拡張子なし名前順)
        table.sort(nodes, function(a, b)
            local a_is_dir = a.type == "directory"
            local b_is_dir = b.type == "directory"
            if a_is_dir ~= b_is_dir then return a_is_dir end
            
            local a_base = vim.fn.fnamemodify(a.text, ":r"):lower()
            local b_base = vim.fn.fnamemodify(b.text, ":r"):lower()
            if a_base == b_base then return a.text:lower() < b.text:lower() end
            return a_base < b_base
        end)

        return nodes
    end

    -- 3. ルート（Default/直下）から開始
    local final_nodes = build_recursive(nil)
    
    -- 直下アイテム（Default属）を追加（build_recursive(nil) でカバーされない場合用）
    for _, item in ipairs(direct_items) do
        local is_dir = vim.fn.isdirectory(item.path) == 1
        table.insert(final_nodes, Tree.Node({
            text = item.name,
            id = "fav_item_" .. unl_path.normalize(item.path),
            path = item.path,
            type = is_dir and "directory" or "file",
            extra = { uep_type = "fs", is_favorite_item = true, project_root = project_root }
        }))
    end
    
    -- 再度ソート
    table.sort(final_nodes, function(a, b)
        local a_is_dir = a.type == "directory"
        local b_is_dir = b.type == "directory"
        if a_is_dir ~= b_is_dir then return a_is_dir end
        local a_base = vim.fn.fnamemodify(a.text, ":r"):lower()
        local b_base = vim.fn.fnamemodify(b.text, ":r"):lower()
        if a_base == b_base then return a.text:lower() < b.text:lower() end
        return a_base < b_base
    end)

    return final_nodes
end

function M.create_root_node(is_expanded, project_root, children)
    local favorites = favorites_cache.load(project_root)
    
    if #favorites == 0 then 
        return nil 
    end

    local final_children = children
    if is_expanded and not final_children then
        final_children = M.create_children_nodes(project_root)
    end

    local node = Tree.Node({
        text = "Favorites",
        id = "root_favorites",
        type = "directory",
        _has_children = true,
        extra = {
            uep_type = M.ROOT_TYPE,
            project_root = project_root
        },
        -- is_expanded = is_expanded -- REMOVED: Do not override method
    }, final_children)

    if is_expanded then
        node:expand()
    end
    
    return node
end

return M

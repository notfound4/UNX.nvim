-- lua/UNX/ui/view/uproject/favorites.lua

local Tree = require("nui.tree")
local unl_path = require("UNL.path")
-- ★修正: UNX内部のキャッシュモジュールを使用
local favorites_cache = require("UNX.cache.favorites")

local M = {}

M.ROOT_TYPE = "favorites_root"

function M.create_children_nodes(project_root)
    local favorites = favorites_cache.load(project_root)
    local nodes = {}
    
    local folder_map = {}
    local folders = {}
    local direct_items = {}

    -- 1. フォルダ定義とアイテムを分離
    for _, item in ipairs(favorites) do
        if item.is_folder then
            table.insert(folders, item)
            folder_map[item.name] = { node = nil, children = {} }
        else
            if item.folder and item.folder ~= "Default" then
                if not folder_map[item.folder] then
                    -- フォルダ定義がないが指定されている場合（削除された場合など）
                    folder_map[item.folder] = { node = nil, children = {} }
                    table.insert(folders, { name = item.folder, is_folder = true })
                end
                table.insert(folder_map[item.folder].children, item)
            else
                table.insert(direct_items, item)
            end
        end
    end

    -- 2. フォルダノードの作成
    for _, f in ipairs(folders) do
        local f_children = {}
        for _, item in ipairs(folder_map[f.name].children) do
            local is_dir = vim.fn.isdirectory(item.path) == 1
            table.insert(f_children, Tree.Node({
                text = item.name,
                id = "fav_item_" .. unl_path.normalize(item.path),
                path = item.path,
                type = is_dir and "directory" or "file",
                extra = { uep_type = "fs", is_favorite_item = true, project_root = project_root }
            }))
        end
        
        -- フォルダ内アイテムを拡張子なしのファイル名でソート
        table.sort(f_children, function(a, b)
            local a_base = vim.fn.fnamemodify(a.text, ":r"):lower()
            local b_base = vim.fn.fnamemodify(b.text, ":r"):lower()
            if a_base == b_base then
                return a.text:lower() < b.text:lower()
            end
            return a_base < b_base
        end)

        table.insert(nodes, Tree.Node({
            text = f.name,
            id = "fav_folder_" .. f.name,
            type = "directory",
            _has_children = #f_children > 0,
            extra = { uep_type = "fs", is_favorite_folder = true, project_root = project_root }
        }, f_children))
    end

    -- フォルダ自体を名前順でソート
    table.sort(nodes, function(a, b) return a.text:lower() < b.text:lower() end)

    -- 3. 直下のアイテムを追加
    local direct_nodes = {}
    for _, item in ipairs(direct_items) do
        local is_dir = vim.fn.isdirectory(item.path) == 1
        table.insert(direct_nodes, Tree.Node({
            text = item.name,
            id = "fav_item_" .. unl_path.normalize(item.path),
            path = item.path,
            type = is_dir and "directory" or "file",
            extra = { uep_type = "fs", is_favorite_item = true, project_root = project_root }
        }))
    end

    -- 直下アイテムも拡張子なしでソート
    table.sort(direct_nodes, function(a, b)
        local a_base = vim.fn.fnamemodify(a.text, ":r"):lower()
        local b_base = vim.fn.fnamemodify(b.text, ":r"):lower()
        if a_base == b_base then
            return a.text:lower() < b.text:lower()
        end
        return a_base < b_base
    end)

    for _, n in ipairs(direct_nodes) do
        table.insert(nodes, n)
    end

    return nodes
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

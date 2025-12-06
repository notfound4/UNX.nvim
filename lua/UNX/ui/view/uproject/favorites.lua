-- lua/UNX/ui/view/uproject/favorites.lua

local Tree = require("nui.tree")
local unl_path = require("UNL.path")
-- ★修正: UNX内部のキャッシュモジュールを使用
local favorites_cache = require("UNX.cache.favorites")

local M = {}

M.ROOT_TYPE = "favorites_root"

function M.create_children_nodes()
    local favorites = favorites_cache.load()
    local nodes = {}
    
    for _, item in ipairs(favorites) do
        -- パスが存在するかチェック
        local is_dir = vim.fn.isdirectory(item.path) == 1
        
        table.insert(nodes, Tree.Node({
            text = item.name,
            id = "fav_" .. unl_path.normalize(item.path),
            path = item.path,
            type = is_dir and "directory" or "file",
            _has_children = is_dir,
            extra = {
                uep_type = "fs",
                is_favorite_item = true
            }
        }))
    end
    
    table.sort(nodes, function(a, b)
        if a.type == b.type then return a.text < b.text end
        return a.type == "directory"
    end)
    
    return nodes
end

function M.create_root_node(is_expanded)
    local favorites = favorites_cache.load()
    
    if #favorites == 0 then 
        return nil 
    end

    local children = nil
    if is_expanded then
        children = M.create_children_nodes()
    end

    local node = Tree.Node({
        text = "Favorites",
        id = "root_favorites",
        type = "directory",
        _has_children = true,
        extra = {
            uep_type = M.ROOT_TYPE,
        }
    }, children)
    
    if is_expanded then node:expand() else node:collapse() end
    
    return node
end

return M

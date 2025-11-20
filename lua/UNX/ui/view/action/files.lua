local unl_api = require("UNL.api")

local M = {}

-- [a] クラスの追加
function M.add(tree)
    local node = tree:get_node()
    if not node then return end
    
    local target_dir = node.path
    -- ファイルの上ならその親ディレクトリをターゲットにする
    if node.type == "file" then
        target_dir = vim.fn.fnamemodify(node.path, ":h")
    end

    if not target_dir then return end

    unl_api.provider.request("ucm.class.new", {
        target_dir = target_dir,
        logger_name = "UNX",
    })
end

-- [d] クラスの削除
function M.delete(tree)
    local node = tree:get_node()
    if not node then return end
    
    if node.type == "file" then
        unl_api.provider.request("ucm.class.delete", {
            file_path = node.path,
            logger_name = "UNX",
        })
    else
        vim.notify("Directory deletion via UCM is not supported yet.", vim.log.levels.WARN)
    end
end

-- [m] ファイルの移動
function M.move(tree)
    local node = tree:get_node()
    if not node then return end
    
    if node.type == "file" then
        unl_api.provider.request("ucm.class.move", {
            file_path = node.path,
            logger_name = "UNX",
        })
    else
        vim.notify("Directory move via UCM is not supported yet.", vim.log.levels.WARN)
    end
end

-- [r] ファイルのリネイム
function M.rename(tree)
    local node = tree:get_node()
    if not node then return end
    
    if node.type == "file" then
        unl_api.provider.request("ucm.class.rename", {
            file_path = node.path,
            logger_name = "UNX",
        })
    else
        vim.notify("Directory rename via UCM is not supported yet.", vim.log.levels.WARN)
    end
end

return M

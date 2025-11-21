local unl_api = require("UNL.api")

local M = {}

-- パスを安全な形式（絶対パス、末尾スラッシュなし、OSセパレータ）に正規化する
local function sanitize_path(path)
    if not path or path == "" then return nil end
    -- 絶対パス化
    local abs_path = vim.fn.fnamemodify(path, ":p")
    -- 末尾のパス区切り文字を削除 (Windowsのドライブ直下 "C:/" 等を除く)
    if abs_path:len() > 3 and (abs_path:sub(-1) == "/" or abs_path:sub(-1) == "\\") then
        abs_path = abs_path:sub(1, -2)
    end
    return abs_path
end

-- [a] クラスの追加
function M.add(tree)
    local node = tree:get_node()
    if not node then return end
    
    local raw_target = node.path
    -- ファイルの上ならその親ディレクトリをターゲットにする
    if node.type == "file" then
        raw_target = vim.fn.fnamemodify(node.path, ":h")
    end

    local target_dir = sanitize_path(raw_target)

    if not target_dir then 
        vim.notify("Invalid target path.", vim.log.levels.ERROR)
        return 
    end

    -- ディレクトリの存在確認
    if vim.fn.isdirectory(target_dir) == 0 then
        vim.notify("Target directory does not exist on disk: " .. target_dir, vim.log.levels.ERROR)
        -- 必要であればここでツリーのリフレッシュを促すことも可能
        return
    end

    unl_api.provider.request("ucm.class.new", {
        target_dir = target_dir,
        logger_name = "UNX",
    })
end

-- [A] ディレクトリの追加
function M.add_directory(tree)
    local node = tree:get_node()
    if not node then return end
    
    local raw_target = node.path
    if node.type == "file" then
        raw_target = vim.fn.fnamemodify(node.path, ":h")
    end
    
    local target_dir = sanitize_path(raw_target)
    if not target_dir then return end

    vim.ui.input({ prompt = "New Directory Name: " }, function(input)
        if not input or input == "" then return end
        
        local new_dir_path = vim.fs.joinpath(target_dir, input)
        
        local ok, err = pcall(vim.fn.mkdir, new_dir_path, "p")
        if ok then
            vim.notify("Directory created: " .. new_dir_path, vim.log.levels.INFO)
            
            local unl_events_ok, unl_events = pcall(require, "UNL.event.events")
            local unl_types_ok, unl_event_types = pcall(require, "UNL.event.types")
            
            if unl_events_ok and unl_types_ok then
                 local mod_info = unl_api.find_module(new_dir_path)
                 
                 if mod_info and mod_info.name then
                     unl_events.publish(unl_event_types.ON_AFTER_MODIFY_DIRECTORY, {
                        status = "success",
                        type = "add",
                        module = { name = mod_info.name }
                     })
                 end
            end
        else
            vim.notify("Failed to create directory: " .. tostring(err), vim.log.levels.ERROR)
        end
    end)
end

-- [d] クラスの削除
function M.delete(tree)
    local node = tree:get_node()
    if not node then return end
    
    if node.type == "file" then
        local file_path = sanitize_path(node.path)
        unl_api.provider.request("ucm.class.delete", {
            file_path = file_path,
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
        local file_path = sanitize_path(node.path)
        unl_api.provider.request("ucm.class.move", {
            file_path = file_path,
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
        local file_path = sanitize_path(node.path)
        unl_api.provider.request("ucm.class.rename", {
            file_path = file_path,
            logger_name = "UNX",
        })
    else
        vim.notify("Directory rename via UCM is not supported yet.", vim.log.levels.WARN)
    end
end

return M

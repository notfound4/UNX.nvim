local unl_api = require("UNL.api")
local fs = require("vim.fs")

local M = {}

-- パスを安全な形式に正規化
local function sanitize_path(path)
    if not path or path == "" then return nil end
    local abs_path = vim.fn.fnamemodify(path, ":p")
    if abs_path:len() > 3 and (abs_path:sub(-1) == "/" or abs_path:sub(-1) == "\\") then
        abs_path = abs_path:sub(1, -2)
    end
    return abs_path:gsub("\\", "/")
end

-- [a] クラスの追加
function M.add(tree)
    local node = tree:get_node()
    if not node then return end
    
    local raw_target = node.path
    if node.type == "file" then
        raw_target = vim.fn.fnamemodify(node.path, ":h")
    end

    local target_dir = sanitize_path(raw_target)
    if not target_dir or vim.fn.isdirectory(target_dir) == 0 then 
        vim.notify("Invalid target directory.", vim.log.levels.ERROR)
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

-- [d] 削除
function M.delete(tree)
    local node = tree:get_node()
    if not node then return end
    
    local path = sanitize_path(node.path)
    if not path then return end

    if node.type == "file" then
        unl_api.provider.request("ucm.class.delete", {
            file_path = path,
            logger_name = "UNX",
        })
    elseif node.type == "directory" then
        local choice = vim.fn.confirm("Delete directory '" .. node.text .. "' and ALL its contents?", "&Yes\n&No", 2)
        if choice == 1 then
            local parent_dir = vim.fn.fnamemodify(path, ":h")
            local mod_info = unl_api.find_module(parent_dir)

            local ok = vim.fn.delete(path, "rf") -- 0 on success
            if ok == 0 then 
                vim.notify("Directory deleted: " .. path, vim.log.levels.INFO)
                
                local unl_events_ok, unl_events = pcall(require, "UNL.event.events")
                local unl_types_ok, unl_event_types = pcall(require, "UNL.event.types")
                if unl_events_ok and unl_types_ok and mod_info and mod_info.name then
                     unl_events.publish(unl_event_types.ON_AFTER_MODIFY_DIRECTORY, {
                        status = "success",
                        type = "delete",
                        module = { name = mod_info.name }
                     })
                end
            else
                vim.notify("Failed to delete directory. Error code: " .. tostring(ok), vim.log.levels.ERROR)
            end
        end
    end
end

-- [m] 移動 (修正: ディレクトリ移動時の親切化 & エラーハンドリング修正)
function M.move(tree)
    local node = tree:get_node()
    if not node then return end
    
    local path = sanitize_path(node.path)
    if not path then return end

    if node.type == "file" then
        -- ファイル移動はUCMに任せる（厳格なチェック）
        unl_api.provider.request("ucm.class.move", {
            file_path = path,
            logger_name = "UNX",
        })
    elseif node.type == "directory" then
        vim.ui.input({ prompt = "Move directory to (absolute path): ", default = path, completion = "dir" }, function(new_path)
            if not new_path or new_path == "" or new_path == path then return end
            
            -- ★追加: 親ディレクトリが存在しない場合は作成する
            local parent_dir = vim.fn.fnamemodify(new_path, ":h")
            if vim.fn.isdirectory(parent_dir) == 0 then
                local create_choice = vim.fn.confirm("Parent directory does not exist. Create it?\n" .. parent_dir, "&Yes\n&No", 1)
                if create_choice == 1 then
                    local ok, err = pcall(vim.fn.mkdir, parent_dir, "p")
                    if not ok then
                         vim.notify("Failed to create parent directory: " .. tostring(err), vim.log.levels.ERROR)
                         return
                    end
                else
                    return -- キャンセル
                end
            end
            
            local choice = vim.fn.confirm("Move directory to '" .. new_path .. "'?", "&Yes\n&No", 2)
            if choice == 1 then
                local mod_info_old = unl_api.find_module(vim.fn.fnamemodify(path, ":h"))

                -- ★修正: vim.loop.fs_rename の戻り値を正しく判定
                -- (pcallの戻り値ではなく、fs_rename自体の戻り値を見る)
                local success, err = vim.loop.fs_rename(path, new_path)
                
                if success then
                    vim.notify("Directory moved.", vim.log.levels.INFO)
                    
                    local unl_events_ok, unl_events = pcall(require, "UNL.event.events")
                    local unl_types_ok, unl_event_types = pcall(require, "UNL.event.types")
                    if unl_events_ok and unl_types_ok then
                         local mod_info_new = unl_api.find_module(new_path)
                         
                         if mod_info_old and mod_info_old.name then
                             unl_events.publish(unl_event_types.ON_AFTER_MODIFY_DIRECTORY, { status="success", type="move", module={name=mod_info_old.name} })
                         end
                         if mod_info_new and mod_info_new.name and (not mod_info_old or mod_info_new.name ~= mod_info_old.name) then
                             unl_events.publish(unl_event_types.ON_AFTER_MODIFY_DIRECTORY, { status="success", type="move", module={name=mod_info_new.name} })
                         end
                    end
                else
                    vim.notify("Failed to move directory: " .. tostring(err), vim.log.levels.ERROR)
                end
            end
        end)
    end
end

-- [r] リネーム
function M.rename(tree)
    local node = tree:get_node()
    if not node then return end
    
    local path = sanitize_path(node.path)
    if not path then return end

    if node.type == "file" then
        unl_api.provider.request("ucm.class.rename", {
            file_path = path,
            logger_name = "UNX",
        })
    elseif node.type == "directory" then
        local old_name = node.text
        vim.ui.input({ prompt = "Rename directory: ", default = old_name }, function(new_name)
            if not new_name or new_name == "" or new_name == old_name then return end
            
            local parent_dir = vim.fn.fnamemodify(path, ":h")
            local new_path = vim.fs.joinpath(parent_dir, new_name)
            
            -- ★修正: エラーハンドリング
            local success, err = vim.loop.fs_rename(path, new_path)
            if success then
                vim.notify("Directory renamed.", vim.log.levels.INFO)
                
                local unl_events_ok, unl_events = pcall(require, "UNL.event.events")
                local unl_types_ok, unl_event_types = pcall(require, "UNL.event.types")
                if unl_events_ok and unl_types_ok then
                     local mod_info = unl_api.find_module(new_path)
                     if mod_info and mod_info.name then
                         unl_events.publish(unl_event_types.ON_AFTER_MODIFY_DIRECTORY, {
                            status = "success",
                            type = "rename",
                            module = { name = mod_info.name }
                         })
                     end
                end
            else
                vim.notify("Failed to rename directory: " .. tostring(err), vim.log.levels.ERROR)
            end
        end)
    end
end

return M

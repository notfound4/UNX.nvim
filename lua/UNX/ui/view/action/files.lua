local unl_api = require("UNL.api")
local fs = require("vim.fs")
local favorites_cache = require("UNX.cache.favorites")

-- ★以下を追加（find_files_recursive用）
local unl_picker = require("UNL.backend.picker")
local unx_config = require("UNX.config")
local unl_path = require("UNL.path")
local unl_buf_open = require("UNL.buf.open")

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

-- [m] 移動
function M.move(tree)
    local node = tree:get_node()
    if not node then return end
    
    local path = sanitize_path(node.path)
    if not path then return end

    if node.type == "file" then
        unl_api.provider.request("ucm.class.move", {
            file_path = path,
            logger_name = "UNX",
        })
    elseif node.type == "directory" then
        vim.ui.input({ prompt = "Move directory to (absolute path): ", default = path, completion = "dir" }, function(new_path)
            if not new_path or new_path == "" or new_path == path then return end
            
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

-- [b] お気に入りトグル
function M.toggle_favorite(tree)
    local node = tree:get_node()
    if not node then return end
    
    local path = sanitize_path(node.path)
    if not path then return end
    
    local added, msg = favorites_cache.toggle(path)
    
    local icon = added and "★ " or "☆ "
    vim.notify(icon .. msg .. ": " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO)
    
    require("UNX.ui.view.uproject").refresh(tree)
end

-- [f] フォルダ以下の全ファイルを検索して開く (再帰的・フラット)
function M.find_files_recursive(tree)
    local node = tree:get_node()
    if not node then return end
    
    -- 対象ディレクトリの決定
    local target_dir = node.path
    if node.type == "file" then
        target_dir = vim.fn.fnamemodify(node.path, ":h")
    end
    target_dir = sanitize_path(target_dir)
    
    if not target_dir then return end

    local dir_name = vim.fn.fnamemodify(target_dir, ":t")
    vim.notify("Fetching files under: " .. dir_name, vim.log.levels.INFO)

    -- 前方一致検索用のプレフィックス準備
    local prefix = unl_path.normalize(target_dir)
    if prefix:sub(-1) ~= "/" then prefix = prefix .. "/" end

    -- UEPから全ファイルを取得 (ScopeはFullにして漏れなく探す)
    unl_api.provider.request("uep.get_project_items", { 
        scope = "full",
        deps_flag = "--deep-deps"
    }, function(ok, items)
        if not ok or not items then
            return vim.notify("Failed to get file list from UEP.", vim.log.levels.ERROR)
        end

        local filtered_items = {}
        for _, item in ipairs(items) do
            -- ディレクトリ自体は除外
            if item.type ~= "directory" then
                local item_path = unl_path.normalize(item.path)
                -- パスがターゲットディレクトリ以下か判定
                if item_path:find(prefix, 1, true) == 1 then
                    table.insert(filtered_items, {
                        display = item.display, -- UEP生成の「モジュール/パス」形式
                        value = item.path,
                        filename = item.path,
                    })
                end
            end
        end

        if #filtered_items == 0 then
            return vim.notify("No files found under " .. dir_name, vim.log.levels.WARN)
        end

        table.sort(filtered_items, function(a, b) return a.display < b.display end)

        -- ピッカー表示
        unl_picker.pick({
            kind = "unx_find_files_recursive",
            title = " Find in: " .. dir_name,
            items = filtered_items,
            conf = unx_config.get(),
            preview_enabled = true,
            devicons_enabled = true,
            on_submit = function(selection)
                if selection then
                    unl_buf_open.safe({ file_path = selection.value, open_cmd = "edit", plugin_name = "UNX" })
                end
            end,
        })
    end)
end

return M

-- lua/UNX/ui/view/uproject.lua

local Tree = require("nui.tree")
local Line = require("nui.line")
local unl_api = require("UNL.api")
local unl_finder = require("UNL.finder")
local fs = require("vim.fs")
local utils = require("UNX.common.utils")
local file_actions = require("UNX.ui.view.action.files")
local unl_open = require("UNL.buf.open")
local unl_path = require("UNL.path")
local unx_vcs = require("UNX.vcs")
local ctx_uproject = require("UNX.context.uproject")

-- Pending Changes ビューロジック
local PendingView = require("UNX.ui.view.uproject.pending")

local unl_events_ok, unl_events = pcall(require, "UNL.event.events")
local unl_types_ok, unl_event_types = pcall(require, "UNL.event.types")

local has_devicons, devicons = pcall(require, "nvim-web-devicons")

local M = {}

local active_tree = nil
local tree_winid = nil
local render_timer = nil

function M.cancel_async_tasks()
    if render_timer then
        render_timer:stop()
        if not render_timer:is_closing() then render_timer:close() end
        render_timer = nil
    end
end

-- ======================================================
-- HELPER FUNCTIONS
-- ======================================================

local function schedule_render()
    if not active_tree then return end
    if not vim.api.nvim_buf_is_valid(active_tree.bufnr) then return end

    if render_timer then
        render_timer:stop()
        if not render_timer:is_closing() then render_timer:close() end
    end
    render_timer = vim.loop.new_timer()
    render_timer:start(200, 0, vim.schedule_wrap(function()
        if render_timer then
            if not render_timer:is_closing() then render_timer:close() end
            render_timer = nil
        end
        
        if active_tree and vim.api.nvim_buf_is_valid(active_tree.bufnr) then 
            active_tree:render() 
        end
    end))
end

local function scan_directory(path)
    local items = {}
    local handle = vim.loop.fs_scandir(path)
    if handle then
        while true do
            local name, type = vim.loop.fs_scandir_next(handle)
            if not name then break end
            local full_path = fs.joinpath(path, name)
            if not name:match("^%.") then 
                local is_dir = (type == "directory")
                table.insert(items, {
                    text = name,
                    id = unl_path.normalize(full_path),
                    path = full_path,
                    type = is_dir and "directory" or "file",
                    _has_children = is_dir
                })
            end
        end
    end
    table.sort(items, function(a, b)
        if a.type == b.type then return a.text < b.text end
        return a.type == "directory"
    end)
    return items
end

-- ======================================================
-- DATA FETCHING
-- ======================================================

local function convert_uep_to_nui(uep_node)
    local children = nil
    if uep_node.children and #uep_node.children > 0 then
        children = {}
        for _, child in ipairs(uep_node.children) do
            table.insert(children, convert_uep_to_nui(child))
        end
    end

    local nui_node = Tree.Node({
        text = uep_node.name,
        id = uep_node.id or (uep_node.path and unl_path.normalize(uep_node.path)),
        path = uep_node.path,
        type = uep_node.type,
        _has_children = uep_node.has_children or (children and #children > 0),
        extra = uep_node.extra, 
    }, children)
    
    if uep_node.id == "logical_root" or (children and #children > 0) then
        nui_node:expand()
    end
    return nui_node
end

local function fetch_root_data(skip_vcs_refresh)
    local conf = require("UNX.config").get()
    local cwd = vim.loop.cwd()
    local project_info = unl_finder.project.find_project(cwd)
    local ctx = ctx_uproject.get()
    
    if project_info then
        ctx.mode = "uep"
        ctx.project_root = project_info.root
        
        local engine_root = unl_finder.engine.find_engine_root(project_info.uproject, {
            engine_override_path = conf.engine_path 
        })
        ctx.engine_root = engine_root
        ctx_uproject.set(ctx)

        if not skip_vcs_refresh then
            unx_vcs.refresh(project_info.root, function()
                vim.schedule(function()
                    if active_tree then
                        -- ここで M.refresh を呼ぶと再帰ループの危険があるので
                        -- 内部的にノード更新を行う
                        local updated_nodes = fetch_root_data(true)
                        active_tree:set_nodes(updated_nodes)
                        active_tree:render()
                    end
                end)
            end)
        end

        local success, result = unl_api.provider.request("uep.build_tree_model", {
            capability = "uep.build_tree_model",
            project_root = project_info.root,
            engine_root = engine_root,
            scope = "Full",
            logger_name = "UNX",
        })

        if success and result and (not result[1] or result[1].type ~= "message") then
            local nui_nodes = {}
            
            -- ★ 修正: 保存された設定 (ctx) に基づいてノードを作成
            -- 自動同期を削除したので、ctx は常に「ユーザーが最後に操作した状態」を保持している
            local pending_node = PendingView.create_root_node(ctx.is_pending_expanded)
            if pending_node then
                table.insert(nui_nodes, pending_node)
            end

            local top_level_uep_nodes = result[1].children or {}
            for _, item in ipairs(top_level_uep_nodes) do
                table.insert(nui_nodes, convert_uep_to_nui(item))
            end
            return nui_nodes
        end
    end

    vim.schedule(function()
        vim.notify("[UNX] Unreal Engine project (.uproject) not found.", vim.log.levels.INFO)
    end)
    
    ctx.mode = "none"
    ctx.project_root = nil
    ctx_uproject.set(ctx)
    
    return {}
end

local function lazy_load_children(tree_instance, parent_node)
    if parent_node:has_children() then return end
    
    if parent_node.extra and parent_node.extra.uep_type == PendingView.ROOT_TYPE then
        local nui_children = PendingView.create_children_nodes()
        tree_instance:set_nodes(nui_children, parent_node:get_id())
        return
    end

    local ctx = ctx_uproject.get()
    
    if ctx.mode == "uep" then
        local success, children = unl_api.provider.request("uep.load_tree_children", {
            capability = "uep.load_tree_children",
            project_root = ctx.project_root, 
            engine_root = ctx.engine_root,   
            node = { 
                id = parent_node.id, 
                path = parent_node.path,
                name = parent_node.text,
                type = parent_node.type,
                extra = parent_node.extra 
            },
            logger_name = "UNX",
        })

        if success and children then
            local nui_children = {}
            for _, item in ipairs(children) do
                table.insert(nui_children, convert_uep_to_nui(item))
            end
            tree_instance:set_nodes(nui_children, parent_node:get_id())
        end
    else
        local children = scan_directory(parent_node.path)
        local nui_children = {}
        for _, item in ipairs(children) do
            table.insert(nui_children, Tree.Node(item))
        end
        tree_instance:set_nodes(nui_children, parent_node:get_id())
    end
end

-- ======================================================
-- COMPONENT LOADERS
-- ======================================================

local COMPONENTS = {
    vcs_status = require("UNX.ui.view.component.vcs"),
    modified_buffer = require("UNX.ui.view.component.modified"),
}

-- ======================================================
-- RENDERER
-- ======================================================

local function prepare_node(node)
    local conf = require("UNX.config").get()
    local line = Line()
    
    line:append(string.rep("  ", node:get_depth() - 1))

    local has_children = node:has_children() or node._has_children
    if has_children then
        local exp_open = conf.uproject.icon.expander_open or ""
        local exp_closed = conf.uproject.icon.expander_closed or ""
        local icon = node:is_expanded() and exp_open or exp_closed
        line:append(icon .. " ", "UNXIndentMarker") 
    else
        line:append("  ", "UNXIndentMarker")
    end

    local icon_text = conf.uproject.icon.default_file or " "
    local icon_hl = "UNXFileIcon"

    local uep_type = node.extra and node.extra.uep_type
    local is_folder_like = (node.type == "directory") or 
                           (uep_type == "category") or 
                           (uep_type == "module_root") or
                           (uep_type == PendingView.ROOT_TYPE)

    if is_folder_like then
        local f_open = conf.uproject.icon.folder_open or ""
        local f_close = conf.uproject.icon.folder_closed or ""
        icon_text = node:is_expanded() and f_open or f_close
        icon_hl = "UNXDirectoryIcon"
        
        if node.text == "Game" then icon_hl = "UNXVCSRenamed" end 
        if node.text == "Engine" then icon_hl = "UNXVCSRenamed" end
        
        if uep_type == PendingView.ROOT_TYPE then
            icon_text = "" -- Diff icon
            icon_hl = "Special"
        end
        
    elseif node.type == "file" and has_devicons then
        local filename = node.text
        local ext = node.path and node.path:match("^.+%.(.+)$") or ""
        local dev_icon, dev_hl = devicons.get_icon(filename, ext, { default = true })
        if dev_icon then icon_text = dev_icon; icon_hl = dev_hl end
        
        if ext == "uproject" then icon_text = "UE"; icon_hl = "UNXVCSAdded" end
        if ext == "uplugin" then icon_text = "UP"; icon_hl = "UNXVCSAdded" end
        if ext == "Build.cs" then icon_text = "🔨"; icon_hl = "Special" end
    end

    line:append(icon_text .. " ", icon_hl)

    local right_components_data = {}
    local right_width = 0
    local component_keys = conf.uproject.ui and conf.uproject.ui.right_components or {}
    
    for _, comp_key in ipairs(component_keys) do
        local comp_fn = COMPONENTS[comp_key]
        if comp_fn then
            local res = comp_fn(node, {}, conf)
            if res then
                if right_width > 0 then
                    table.insert(right_components_data, { text = " ", highlight = "Normal" })
                    right_width = right_width + 1
                end
                table.insert(right_components_data, res)
                right_width = right_width + vim.fn.strdisplaywidth(res.text)
            end
        end
    end

    local path = node.path or node.id
    local norm_path = unl_path.normalize(path)
    
    local vcs_stat = unx_vcs.get_status(norm_path)
    
    local name_hl = "UNXFileName"
    if vcs_stat then 
        _, name_hl = utils.get_vcs_icon_and_hl(vcs_stat, conf)
    end

    local display_text = node.text

    if tree_winid and vim.api.nvim_win_is_valid(tree_winid) then
        local win_width = vim.api.nvim_win_get_width(tree_winid)
        local current_left_width = line:width()
        local available_width = win_width - current_left_width - right_width - 2
        
        if available_width < 1 then available_width = 1 end
        
        if vim.fn.strdisplaywidth(display_text) > available_width then
            while vim.fn.strdisplaywidth(display_text) > available_width and #display_text > 0 do
                display_text = vim.fn.strcharpart(display_text, 0, vim.fn.strchars(display_text) - 1)
            end
        end
    end

    line:append(display_text, name_hl)
    
    if right_width > 0 and tree_winid and vim.api.nvim_win_is_valid(tree_winid) then
        local win_width = vim.api.nvim_win_get_width(tree_winid)
        local current_width = line:width()
        
        local padding = win_width - current_width - right_width - 2
        
        if padding > 0 then
            line:append(string.rep(" ", padding))
        else
             line:append(" ")
        end
        
        for _, comp in ipairs(right_components_data) do
            line:append(comp.text, comp.highlight)
        end
    end

    return line
end

-- ======================================================
-- PUBLIC API
-- ======================================================

function M.setup()
    
    -- 1. 重い更新 (データ構造再構築)
    vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShellPost", "FocusGained", "DirChanged" }, {
        callback = function()
            local cwd = vim.loop.cwd()
            local current_project_root = unl_finder.project.find_project_root(cwd)

            if not active_tree or not current_project_root then 
                return 
            end

            -- ★ 自動同期ロジック (sync_pending_state_from_tree) はここで削除済み

            unx_vcs.refresh(current_project_root, function()
                vim.schedule(function()
                    M.refresh(active_tree) 
                end)
            end)
        end
    })

    -- 2. 軽い更新 (見た目だけ)
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufModifiedSet", "WinResized", "VimResized" }, {
        callback = function()
            if active_tree then
                schedule_render()
            end
        end
    })

    if unl_events_ok and unl_types_ok then
        local function on_cache_updated()
            local ctx = ctx_uproject.get()
            if active_tree and ctx.project_root then
                 vim.schedule(function()
                    M.refresh(active_tree)
                end)
            end
        end

        unl_events.subscribe(unl_event_types.ON_AFTER_UEP_LIGHTWEIGHT_REFRESH, on_cache_updated)
        unl_events.subscribe(unl_event_types.ON_AFTER_REFRESH_COMPLETED, on_cache_updated)
    end
end

function M.create(bufnr, winid)
    local conf = require("UNX.config").get()
    tree_winid = winid
    active_tree = Tree({
        bufnr = bufnr,
        nodes = fetch_root_data(),
        prepare_node = prepare_node,
    })

    local map_opts = { buffer = bufnr, noremap = true, silent = true }
    local keys = conf.keymaps or {}
    
    if keys.action_add then
        vim.keymap.set("n", keys.action_add, function() file_actions.add(active_tree) end, map_opts)
    end
    if keys.action_add_directory then
        vim.keymap.set("n", keys.action_add_directory, function() file_actions.add_directory(active_tree) end, map_opts)
    end
    if keys.action_delete then
        vim.keymap.set("n", keys.action_delete, function() file_actions.delete(active_tree) end, map_opts)
    end
    if keys.action_move then
        vim.keymap.set("n", keys.action_move, function() file_actions.move(active_tree) end, map_opts)
    end
    if keys.action_rename then
        vim.keymap.set("n", keys.action_rename, function() file_actions.rename(active_tree) end, map_opts)
    end

    return active_tree
end

function M.refresh(tree_instance, winid)
    if tree_instance then
        -- 自動同期ロジック (sync_pending_state_from_tree) はここで削除済み

        if winid and vim.api.nvim_win_is_valid(winid) then
            tree_winid = winid
        end

        local new_nodes = fetch_root_data()
        tree_instance:set_nodes(new_nodes)
        tree_instance:render()
        active_tree = tree_instance
    end
end

function M.on_node_action(tree_instance, split_instance, other_split_instance)
    local node = tree_instance:get_node()
    if not node then return end
    
    if node:has_children() or node._has_children or node.type == "directory" then
        if node:is_expanded() then
            node:collapse()
        else
            if not node:has_children() then
                lazy_load_children(tree_instance, node)
            end
            node:expand()
        end
        
        -- ★ 重要: 唯一の保存ポイント
        -- ユーザーが手動で開閉した時だけ、状態を保存する
        if node.extra and node.extra.uep_type == PendingView.ROOT_TYPE then
            local ctx = ctx_uproject.get()
            ctx.is_pending_expanded = node:is_expanded()
            ctx_uproject.set(ctx)
        end

        tree_instance:render()
    else
        if node.path then
             unl_open.safe({
                file_path = node.path,
                open_cmd = "edit",
                plugin_name = "UNX",
                split_cmd = "vertical botright split",
            })
        end
    end
end

return M

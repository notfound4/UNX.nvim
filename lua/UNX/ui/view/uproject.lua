-- lua/UNX/ui/view/uproject.lua

local Tree = require("nui.tree")
local Line = require("nui.line")
local unl_api = require("UNL.api")
local unl_finder = require("UNL.finder")
local unl_context = require("UNL.context") -- Added
local fs = require("vim.fs")
local utils = require("UNX.common.utils")
local file_actions = require("UNX.ui.view.action.files")
local diff_action = require("UNX.ui.view.action.diff")
local unl_open = require("UNL.buf.open")
local unl_path = require("UNL.path")
local unx_vcs = require("UNX.vcs")
local ctx_uproject = require("UNX.context.uproject")

-- ビューロジックの読み込み
local PendingView = require("UNX.ui.view.uproject.pending")
local FavoritesView = require("UNX.ui.view.uproject.favorites") -- ★追加

local unl_events_ok, unl_events = pcall(require, "UNL.event.events")
local unl_types_ok, unl_event_types = pcall(require, "UNL.event.types")

local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local cache = require("UNX.cache")

local M = {}

local TREE_STATE_CACHE_ID = "uproject_tree_state"
local active_tree = nil
local tree_winid = nil
local render_timer = nil
local save_timer = nil
local expanded_state = {}


function M.cancel_async_tasks()
    if render_timer then
        render_timer:stop()
        if not render_timer:is_closing() then render_timer:close() end
        render_timer = nil
    end
    if save_timer then
        save_timer:stop()
        if not save_timer:is_closing() then save_timer:close() end
        save_timer = nil
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

-- ======================================================
-- HELPER: File System Scan (Direct, No Cache)
-- ======================================================

local IGNORED_DIRS = {
    [".git"] = true,
    [".vs"] = true,
    [".vscode"] = true,
    [".idea"] = true,
    ["Intermediate"] = true,
    ["Binaries"] = true,
    ["Saved"] = true,
    ["DerivedDataCache"] = true,
    ["Build"] = true,
}

local function is_ignored(name)
    return IGNORED_DIRS[name] == true
end

local function scan_directory(path, exclude_paths)
    if not path then return {} end
    exclude_paths = exclude_paths or {}
    
    local items = {}
    local handle = vim.loop.fs_scandir(path)
    if handle then
        while true do
            local name, type = vim.loop.fs_scandir_next(handle)
            if not name then break end
            
            local full_path = fs.joinpath(path, name)
            local normalized = unl_path.normalize(full_path)
            
            if not name:match("^%.") and not is_ignored(name) and not exclude_paths[normalized] then 
                local is_dir = (type == "directory")
                
                table.insert(items, {
                    text = name,
                    id = normalized,
                    path = full_path,
                    type = is_dir and "directory" or "file",
                    _has_children = is_dir
                })
            end
        end
    end
    
    table.sort(items, function(a, b)
        if a.type == b.type then return a.text < b.text end
        return a.type == "directory" -- ディレクトリ優先
    end)
    
    -- NUI Node形式に変換
    local nodes = {}
    for _, item in ipairs(items) do
        table.insert(nodes, Tree.Node({
            text = item.text,
            id = item.id,
            path = item.path,
            type = item.type,
            _has_children = item._has_children
        }))
    end
    
    return nodes
end

-- ======================================================
-- HELPER: State Sync
-- ======================================================

local function get_current_pending_states()
    local states = {}
    
    local ctx = ctx_uproject.get()
    if type(ctx.pending_states) ~= "table" then
        ctx.pending_states = {
            [PendingView.ROOT_TYPE_PENDING] = (ctx.is_pending_expanded ~= false)
        }
    end
    states = vim.deepcopy(ctx.pending_states)

    if active_tree then
        local p_node = active_tree:get_node("root_pending_changes")
        if p_node then states[PendingView.ROOT_TYPE_PENDING] = p_node:is_expanded() end
        
        local u_node = active_tree:get_node("root_unpushed_commits")
        if u_node then states[PendingView.ROOT_TYPE_UNPUSHED] = u_node:is_expanded() end
    end
    
    ctx.pending_states = states
    ctx_uproject.set(ctx)
    
    return states
end

-- ======================================================
-- HELPER: Tree State Restoration
-- ======================================================

local lazy_load_children -- Forward declaration

local function restore_expansion(tree, expanded_ids, nodes_list)
    local roots = nodes_list or tree:get_nodes()
    
    local function process(process_nodes_list)
        for _, node in ipairs(process_nodes_list) do
            if expanded_ids[node:get_id()] then
                if node:has_children() or node._has_children then
                     if not node:is_expanded() then
                         if not node:has_children() and lazy_load_children then
                              lazy_load_children(tree, node)
                         end
                         node:expand()
                         
                         local children = tree:get_nodes(node:get_id())
                         if children then process(children) end
                     end
                end
            end
        end
    end
    
    process(roots)
end

function M.save_tree_state()
    if save_timer then
        save_timer:stop()
        if not save_timer:is_closing() then save_timer:close() end
    end
    save_timer = vim.loop.new_timer()
    save_timer:start(500, 0, vim.schedule_wrap(function()
        if save_timer then
            if not save_timer:is_closing() then save_timer:close() end
            save_timer = nil
        end
        if active_tree and vim.api.nvim_buf_is_valid(active_tree.bufnr) then
            local ctx = ctx_uproject.get()
            if ctx.project_root then
                cache.write(TREE_STATE_CACHE_ID, ctx.project_root, expanded_state)
            end
        end
    end))
end



-- ======================================================

-- DATA FETCHING

-- ======================================================

local function fetch_root_data(skip_vcs_refresh)
    local conf = require("UNX.config").get()
    local cwd = vim.loop.cwd()
    
    -- UNX: Check for UEP Module Tree override
    local uep_payload = unl_context.use("UEP"):key("last_tree_payload"):get("payload")
    local is_module_mode = (uep_payload and uep_payload.scope == "Module" and uep_payload.module_root)

    -- プロジェクトルートの検出 (UEPに依存せずUNL.finderを使用)
    local project_info = unl_finder.project.find_project(cwd)
    local ctx = ctx_uproject.get()
    
    if project_info then
        ctx.mode = "uep" -- 便宜上UEPモードとするが、実質はファイルシステムモード
        ctx.project_root = project_info.root
        
        local engine_root = unl_finder.engine.find_engine_root(project_info.uproject, {
            engine_override_path = conf.engine_path 
        })
        ctx.engine_root = engine_root
        ctx_uproject.set(ctx)

        -- VCSリフレッシュ (非同期)
        if not skip_vcs_refresh then
            unx_vcs.refresh(project_info.root, function()
                vim.schedule(function()
                    if active_tree then
                        -- VCSの状態が変わるとノード構成（Pending Changes等）が変わる可能性があるため、再構築する
                        local expanded = expanded_state
                        local updated_nodes = fetch_root_data(true)
                        active_tree:set_nodes(updated_nodes)
                        restore_expansion(active_tree, expanded)
                        active_tree:render()
                    end
                end)
            end)
        end

        local nui_nodes = {}

        -- ★★★ 1. Favorites (Common) ★★★
        local is_fav_exp = ctx.is_favorites_expanded
        if is_fav_exp == nil then is_fav_exp = true end
        
        if active_tree then
                local f_node = active_tree:get_node("root_favorites")
                if f_node then 
                    is_fav_exp = f_node:is_expanded()
                    if ctx.is_favorites_expanded ~= is_fav_exp then
                        ctx.is_favorites_expanded = is_fav_exp
                        ctx_uproject.set(ctx)
                    end
                end
        end
        
        local fav_node = FavoritesView.create_root_node(is_fav_exp)
        if fav_node then 
            table.insert(nui_nodes, fav_node) 
        end

        -- ★★★ 2. Pending Changes / Unpushed (Common) ★★★
        local pending_states = get_current_pending_states()
        local pending_nodes_list = PendingView.create_root_nodes(pending_states)
        for _, p_node in ipairs(pending_nodes_list) do
            table.insert(nui_nodes, p_node)
        end

        if is_module_mode then
             -- [UEP Module Mode] Display only the target module
             local mod_root = unl_path.normalize(uep_payload.module_root)
             local mod_name = uep_payload.target_module or vim.fn.fnamemodify(mod_root, ":t")
             
             local mod_node = Tree.Node({
                text = mod_name,
                id = mod_root,
                path = uep_payload.module_root, -- keep original for fs ops? or use normalized? best to match scan
                type = "directory",
                _has_children = true,
                extra = { uep_type = "fs" }
            })
            mod_node:expand()
            table.insert(nui_nodes, mod_node)
            
            return nui_nodes
        end

        -- [Standard Mode] Project + Engine

        -- ★★★ 3. Project Root Node ★★★
        local project_name = vim.fn.fnamemodify(project_info.root, ":t")
        -- Engineルートがプロジェクトを含む場合や名前衝突を避けるため、プロジェクトルートIDは通常化パスを使用する
        -- ID重複問題("Project ID" vs "Engine Child ID")は、scan_directoryでEngineスキャン時にプロジェクトを除外することで解決する
        local project_node = Tree.Node({
            text = project_name,
            id = unl_path.normalize(project_info.root),
            path = project_info.root,
            type = "directory",
            _has_children = true,
            extra = { uep_type = "fs" } -- ファイルシステムノード識別子
        })
        project_node:expand() -- デフォルト展開
        table.insert(nui_nodes, project_node)

        -- ★★★ 4. Engine Root Node ★★★
        if engine_root then
             local engine_node = Tree.Node({
                text = "Engine",
                id = unl_path.normalize(engine_root),
                path = engine_root,
                type = "directory",
                _has_children = true,
                extra = { uep_type = "fs" }
            })
            table.insert(nui_nodes, engine_node)
        end

        return nui_nodes
    end

    vim.schedule(function()
        vim.notify("[UNX] Unreal Engine project (.uproject) not found.", vim.log.levels.INFO)
    end)
    
    ctx.mode = "none"
    ctx.project_root = nil
    ctx_uproject.set(ctx)
    
    return {}
end

lazy_load_children = function(tree_instance, parent_node)
    if parent_node:has_children() then return end
    
    -- 1. Pending Changes / Unpushed Commits
    if parent_node.extra and (parent_node.extra.uep_type == PendingView.ROOT_TYPE_PENDING or parent_node.extra.uep_type == PendingView.ROOT_TYPE_UNPUSHED) then
        local nui_children = PendingView.create_children_nodes(parent_node)
        tree_instance:set_nodes(nui_children, parent_node:get_id())
        return
    end

    -- 2. Favorites
    if parent_node.extra and parent_node.extra.uep_type == FavoritesView.ROOT_TYPE then
        local nui_children = FavoritesView.create_children_nodes()
        tree_instance:set_nodes(nui_children, parent_node:get_id())
        return
    end

    -- 3. File System (UEPリクエスト廃止 -> 直接スキャン)
    if parent_node.path then
        local exclude = {}
        
        -- もし自分がEngineルートの下にいる、あるいはEngineルートそのものであれば、
        -- プロジェクトのディレクトリが表示されて重複するのを防ぐために除外リストを作成する
        local ctx = ctx_uproject.get()
        if ctx.project_root and ctx.engine_root then
             local p_norm = unl_path.normalize(parent_node.path)
             local e_norm = unl_path.normalize(ctx.engine_root)
             
             -- 簡易的なサブパス判定
             local is_sub = (p_norm == e_norm) or (vim.startswith(p_norm, e_norm .. "/"))
             
             if is_sub then
                 exclude[unl_path.normalize(ctx.project_root)] = true
             end
        end
        
        local children_data = scan_directory(parent_node.path, exclude)
        
        -- Favorites内の物理スキャンの場合もフラグを引き継ぐ
        if parent_node.extra and parent_node.extra.is_favorite_item then
            for _, item in ipairs(children_data) do
                 if not item.extra then item.extra = {} end
                 item.extra.uep_type = "fs"
                 item.extra.is_favorite_item = true
            end
        end
        tree_instance:set_nodes(children_data, parent_node:get_id())
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
                           (uep_type == PendingView.ROOT_TYPE_PENDING) or
                           (uep_type == PendingView.ROOT_TYPE_UNPUSHED) or
                           (uep_type == FavoritesView.ROOT_TYPE) -- ★追加

    if is_folder_like then
        local f_open = conf.uproject.icon.folder_open or ""
        local f_close = conf.uproject.icon.folder_closed or ""
        icon_text = node:is_expanded() and f_open or f_close
        icon_hl = "UNXDirectoryIcon"
        
        if node.text == "Game" then icon_hl = "UNXVCSRenamed" end 
        if node.text == "Engine" then icon_hl = "UNXVCSRenamed" end
        
        if uep_type == PendingView.ROOT_TYPE_PENDING then
            icon_text = "" -- Diff icon
            icon_hl = "Special"
        elseif uep_type == PendingView.ROOT_TYPE_UNPUSHED then
            icon_text = "" -- Upload icon
            icon_hl = "Special"
        elseif uep_type == FavoritesView.ROOT_TYPE then
            -- ★追加: Favorites アイコン
            icon_text = "" -- Star icon
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
    
    -- Unpushed アイテムの強調表示
    if node.extra and node.extra.vcs_status_override == "Unpushed" then
        name_hl = "UNXVCSAdded"
    end
    
    -- ★追加: お気に入りアイテムの強調表示 (例えば名前を黄色にする等、お好みで)
    if node.extra and node.extra.is_favorite_item then
        -- name_hl = "Special" -- 必要であればコメントアウトを外す
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
    vim.api.nvim_create_autocmd({ "VimLeave" }, {
        callback = function()
            if active_tree and vim.api.nvim_buf_is_valid(active_tree.bufnr) then
                local ctx = ctx_uproject.get()
                if ctx.project_root then
                    cache.write(TREE_STATE_CACHE_ID, ctx.project_root, expanded_state)
                end
            end
        end,
    })
    
    vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShellPost", "FocusGained", "DirChanged" }, {
        callback = function()
            local explorer_ui = require("UNX.ui.explorer")
            if not explorer_ui.is_open() then return end
            
            if not active_tree or not vim.api.nvim_buf_is_valid(active_tree.bufnr) then
                return
            end

            local cwd = vim.loop.cwd()
            local current_project_root = unl_finder.project.find_project_root(cwd)

            if not current_project_root then 
                return 
            end

            unx_vcs.refresh(current_project_root, function()
                vim.schedule(function()
                    if explorer_ui.is_open() and active_tree and vim.api.nvim_buf_is_valid(active_tree.bufnr) then
                        M.refresh(active_tree)
                    end
                end)
            end)
        end
    })

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

    -- Restore expansion state from cache
    local ctx = ctx_uproject.get()
    if ctx.project_root then
        local loaded_state = cache.read(TREE_STATE_CACHE_ID, ctx.project_root)
        if loaded_state and type(loaded_state) == "table" then
            expanded_state = loaded_state
        end

        if not vim.tbl_isempty(expanded_state) then
            restore_expansion(active_tree, expanded_state)
            active_tree:render()
        end
    end

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
    
    -- ★追加: Favoritesトグルキーマップ
    if keys.action_toggle_favorite then
        vim.keymap.set("n", keys.action_toggle_favorite, function() file_actions.toggle_favorite(active_tree) end, map_opts)
    end

    if keys.action_find_files then
        vim.keymap.set("n", keys.action_find_files, function() file_actions.find_files_recursive(active_tree) end, map_opts)
    end

    if keys.action_force_refresh then
        vim.keymap.set("n", keys.action_force_refresh, function() file_actions.refresh(active_tree) end, map_opts)
    end
    
    if keys.action_diff then
        vim.keymap.set("n", keys.action_diff, function() diff_action.diff(active_tree) end, map_opts)
    end

    if keys.custom then
        for key, func in pairs(keys.custom) do
            vim.keymap.set("n", key, function() 
                if type(func) == "function" then
                    func(active_tree)
                elseif type(func) == "string" then
                    vim.cmd(func)
                end
            end, map_opts)
        end
    end

    return active_tree
end

function M.refresh(tree_instance, winid, opts)
    opts = opts or {}
    if tree_instance and vim.api.nvim_buf_is_valid(tree_instance.bufnr) then
        if winid and vim.api.nvim_win_is_valid(winid) then
            tree_winid = winid
        end

        -- Keep the current state, just rebuild the nodes
        local new_nodes = fetch_root_data(opts.skip_vcs)
        tree_instance:set_nodes(new_nodes)
        restore_expansion(tree_instance, expanded_state)
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
            expanded_state[node:get_id()] = nil
        else
            if not node:has_children() then
                lazy_load_children(tree_instance, node)
            end
            node:expand()
            expanded_state[node:get_id()] = true

            -- Restore expansion for children of the newly expanded node
            local children = tree_instance:get_nodes(node:get_id())
            if children then
                restore_expansion(tree_instance, expanded_state, children)
            end
        end
        
        -- 手動操作時の状態保存
        local uep_type = node.extra and node.extra.uep_type
        local ctx = ctx_uproject.get()

        if uep_type == PendingView.ROOT_TYPE_PENDING or uep_type == PendingView.ROOT_TYPE_UNPUSHED then
            if not ctx.pending_states then ctx.pending_states = {} end
            ctx.pending_states[uep_type] = node:is_expanded()
            ctx_uproject.set(ctx)
            
        elseif uep_type == FavoritesView.ROOT_TYPE then
            -- ★追加: Favoritesの状態保存
            ctx.is_favorites_expanded = node:is_expanded()
            ctx_uproject.set(ctx)
        end

        tree_instance:render()
        M.save_tree_state()
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

function M.ensure_children_loaded(tree, node)
    if not node:has_children() then
        lazy_load_children(tree, node)
    end
end

function M.set_expanded_state(node_id, is_expanded)
    if is_expanded then
        expanded_state[node_id] = true
    else
        expanded_state[node_id] = nil
    end
end

return M

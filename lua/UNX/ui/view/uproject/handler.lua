-- lua/UNX/ui/view/uproject/handler.lua
local unl_open = require("UNL.buf.open")
local unl_finder = require("UNL.finder")
local unx_vcs = require("UNX.vcs")
local ctx_uproject = require("UNX.context.uproject")
local cache = require("UNX.cache")
local file_actions = require("UNX.ui.view.action.files")
local diff_action = require("UNX.ui.view.action.diff")
local filter_action = require("UNX.ui.view.action.filter")

local PendingView = require("UNX.ui.view.uproject.pending")
local FavoritesView = require("UNX.ui.view.uproject.favorites")
local favorite_actions = require("UNX.ui.view.action.favorites")

local M = {}

M.TREE_STATE_CACHE_ID = "uproject_tree_state"

function M.setup_autocmds(view_mod, schedule_render_fn)
    vim.api.nvim_create_autocmd({ "VimLeave" }, {
        callback = function()
            local tree = view_mod.get_active_tree()
            local exp_state = view_mod.get_expanded_state()
            if tree and vim.api.nvim_buf_is_valid(tree.bufnr) then
                local ctx = ctx_uproject.get()
                if ctx.project_root then
                    cache.write(M.TREE_STATE_CACHE_ID, ctx.project_root, exp_state)
                end
            end
        end,
    })

    vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShellPost", "FocusGained", "DirChanged" }, {
        callback = function()
            local explorer_ui = require("UNX.ui.explorer")
            if not explorer_ui.is_open() then return end
            
            local tree = view_mod.get_active_tree()
            if not tree or not vim.api.nvim_buf_is_valid(tree.bufnr) then return end

            local current_project_root = unl_finder.project.find_project_root(vim.loop.cwd())
            if not current_project_root then return end

            unx_vcs.refresh(current_project_root, function()
                vim.schedule(function()
                    if explorer_ui.is_open() and tree and vim.api.nvim_buf_is_valid(tree.bufnr) then     
                        view_mod.refresh(tree)
                    end
                end)
            end)
        end,
    })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufModifiedSet", "WinResized", "VimResized" }, {     
        callback = function()
            if view_mod.get_active_tree() then schedule_render_fn() end
        end
    })
end

function M.apply_keymaps(bufnr, active_tree, conf)
    local map_opts = { buffer = bufnr, noremap = true, silent = true }
    local keys = conf.keymaps or {}

    local mappings = {
        action_add = file_actions.add,
        action_add_directory = file_actions.add_directory,
        action_delete = file_actions.delete,
        action_move = file_actions.move,
        action_rename = file_actions.rename,
        action_toggle_favorite = file_actions.toggle_favorite,
        action_add_favorite_folder = favorite_actions.add_folder,
        action_move_favorite = favorite_actions.move_item,
        action_move_favorite_another = favorite_actions.move_item,
        action_rename_favorite_folder = favorite_actions.rename_folder,
        action_remove_favorite_folder = favorite_actions.remove_folder,
        action_find_files = file_actions.find_files_recursive,
        action_force_refresh = file_actions.refresh,
        action_diff = diff_action.diff,
        action_open_in_ide = file_actions.open_in_ide,
    }

    for key_id, fn in pairs(mappings) do
        if keys[key_id] then
            vim.keymap.set("n", keys[key_id], function() fn(active_tree) end, map_opts)
        end
    end

    vim.keymap.set("n", "/", function() filter_action.start_filter(active_tree) end, map_opts)

    if keys.custom then
        for key, func in pairs(keys.custom) do
            vim.keymap.set("n", key, function()
                if type(func) == "function" then func(active_tree)
                elseif type(func) == "string" then vim.cmd(func) end
            end, map_opts)
        end
    end
end

function M.on_node_action(tree_instance, builder_mod, expanded_state, save_state_fn)
    local node = tree_instance:get_node()
    if not node then return end

    local node_id = node:get_id()

    if node:has_children() or node._has_children or node.type == "directory" then
        if node:is_expanded() then
            node:collapse()
            expanded_state[node_id] = false
        else
            if not node:has_children() then builder_mod.lazy_load_children(tree_instance, node) end
            node:expand()
            expanded_state[node_id] = true
            
            -- 子ノードの展開状態を復元
            local children = tree_instance:get_nodes(node_id)
            if children then
                M.restore_expansion(tree_instance, expanded_state, builder_mod, children)
            end
        end

        -- Contextへの同期
        local uep_type = node.extra and node.extra.uep_type
        local ctx = ctx_uproject.get()
        local is_exp = node:is_expanded()

        if uep_type == PendingView.ROOT_TYPE_PENDING or uep_type == PendingView.ROOT_TYPE_UNPUSHED then
            if not ctx.pending_states then ctx.pending_states = {} end
            ctx.pending_states[uep_type] = is_exp
            ctx_uproject.set(ctx)
        elseif uep_type == FavoritesView.ROOT_TYPE then
            ctx.is_favorites_expanded = is_exp
            ctx_uproject.set(ctx)
        end

        tree_instance:render()
        save_state_fn()
    else
        if node.path then
            unl_open.safe({ file_path = node.path, open_cmd = "edit", plugin_name = "UNX", split_cmd = "vertical botright split" })
        end
    end
end

function M.restore_expansion(tree, expanded_ids, builder_mod, nodes_list)
    local roots = nodes_list or tree:get_nodes()
    
    for _, node in ipairs(roots) do
        local is_folder = node:has_children() or node._has_children or node.type == "directory"
        if is_folder then
            local node_id = node:get_id()
            if expanded_ids[node_id] then
                -- 展開
                if not node:has_children() then 
                    builder_mod.lazy_load_children(tree, node) 
                end
                node:expand()
                
                local children = tree:get_nodes(node_id)
                if children and #children > 0 then
                    M.restore_expansion(tree, expanded_ids, builder_mod, children)
                end
            else
                -- キャッシュで明示的に閉じられている、または未踏の場合は閉じる
                node:collapse()
            end
        end
    end
end

return M

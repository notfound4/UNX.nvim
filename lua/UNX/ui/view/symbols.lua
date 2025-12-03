-- lua/UNX/ui/view/symbols.lua
local Tree = require("nui.tree")
local Line = require("nui.line")
local unl_api = require("UNL.api")
local IDRegistry = require("UNX.common.id_registry")
local logger = require("UNX.logger")
local unl_open = require("UNL.buf.open")

local SymbolParser = require("UNX.parser.symbols")
local ctx_symbols = require("UNX.context.symbols")

local M = {}

local runtime_state = {
    ticks = {},
    tree_ref = nil,
    cancel_func = nil,
    ignore_next_update = false,
}

local debounce_timer = nil

local function prepare_node(node)
    local line = Line()
    line:append(string.rep("  ", node:get_depth() - 1))
    
    local icon, icon_hl, text_hl = " ", "Normal", "UNXFileName"
    
    -- ★★★ 修正: 新しい UNXVCS グループを適用 ★★★
    if node.kind == "UClass" then icon = "UE "; icon_hl = "UNXVCSAdded"; text_hl = "Type"
    elseif node.kind == "UStruct" then icon = "US "; icon_hl = "UNXVCSAdded"; text_hl = "Type"
    elseif node.kind == "UEnum" then icon = "En "; icon_hl = "UNXVCSAdded"; text_hl = "Type"
    elseif node.kind == "Class" then icon = "󰌗 "; icon_hl = "Type"; text_hl = "Type"
    elseif node.kind == "Struct" then icon = "󰌗 "; icon_hl = "Type"; text_hl = "Type"
    
    -- 関数系に UNXVCSFunction を適用
    elseif node.kind == "UFunction" then icon = "UF "; icon_hl = "UNXVCSModified"; text_hl = "UNXVCSFunction"
    elseif node.kind == "Function" then icon = "󰊕 "; icon_hl = "UNXVCSFunction"
    
    elseif node.kind == "Constructor" then icon = " "; icon_hl = "Special"
    elseif node.kind == "UProperty" then icon = "UP "; icon_hl = "UNXDirectoryIcon"
    elseif node.kind == "Field" then icon = " "; icon_hl = "Identifier"
    elseif node.kind == "Access" then icon = " "; icon_hl = "Special"; text_hl = "Special"
    elseif node.kind == "GroupFields" then icon = " "; icon_hl = "Special"; text_hl = "Title"
    elseif node.kind == "GroupMethods" then icon = "󰊕 "; icon_hl = "Special"; text_hl = "Title"
    elseif node.kind == "BaseClass" then icon = "󰜮 "; icon_hl = "UNXVCSRenamed"; text_hl = "Comment"
    elseif node.kind == "Implementation" then icon = " "; icon_hl = "Comment"; text_hl = "Comment"
    elseif node.kind == "Info" then icon = " "; icon_hl = "Comment"
    end
    
    line:append(icon, icon_hl)
    line:append(node.text, text_hl)
    
    if node.detail and node.detail ~= "" then
        line:append(node.detail, "Comment")
    end

    return line
end

function M.setup()
end

function M.create(bufnr)
    return Tree({
        bufnr = bufnr,
        nodes = {},
        prepare_node = prepare_node,
    })
end

function M.update(tree_instance, target_winid, opts)
    if not tree_instance then return end
    opts = opts or {}
    
    local current_buf = vim.api.nvim_get_current_buf()
    local buf_name = vim.api.nvim_buf_get_name(current_buf)
    if buf_name == "" then return end

    local ft = vim.bo[current_buf].filetype
    if ft == "unx-explorer" or ft == "neo-tree" or ft == "TelescopePrompt" or ft == "qf" then return end

    local debounce_delay = 50
    if debounce_timer then
        debounce_timer:stop()
        if not debounce_timer:is_closing() then debounce_timer:close() end
        debounce_timer = nil
    end

    debounce_timer = vim.loop.new_timer()
    debounce_timer:start(debounce_delay, 0, vim.schedule_wrap(function()
        if debounce_timer then
            if not debounce_timer:is_closing() then debounce_timer:close() end
            debounce_timer = nil
        end
        
        local current_buf_delayed = vim.api.nvim_get_current_buf()
        local buf_name_delayed = vim.api.nvim_buf_get_name(current_buf_delayed)
        if buf_name_delayed == "" then return end
        local filename = vim.fn.fnamemodify(buf_name_delayed, ":t:r")
        if not filename or filename == "" then return end
        local current_tick = vim.api.nvim_buf_get_changedtick(current_buf_delayed)

        local state = ctx_symbols.get()
        local last_class_name = state.class_name
        local last_bufnr = state.last_bufnr

        if runtime_state.ignore_next_update then
            runtime_state.ignore_next_update = false
            state.last_bufnr = current_buf_delayed
            ctx_symbols.set(state)
            runtime_state.ticks[current_buf_delayed] = current_tick
            logger.get().trace("Skipping symbol tree update (Explicit ignore from action)")
            return
        end

        if last_class_name == filename and last_bufnr ~= current_buf_delayed and not opts.force then
            state.last_bufnr = current_buf_delayed
            ctx_symbols.set(state)
            runtime_state.ticks[current_buf_delayed] = current_tick
            logger.get().trace("Skipping symbol tree update for context switch: " .. filename)
            return
        end

        if not opts.force and last_class_name == filename 
           and runtime_state.ticks[current_buf_delayed] == current_tick 
           and runtime_state.tree_ref == tree_instance then
            return
        end

        if runtime_state.cancel_func then
            runtime_state.cancel_func()
            runtime_state.cancel_func = nil
        end

        local is_cancelled = false
        runtime_state.cancel_func = function() is_cancelled = true end

        logger.get().debug("Requesting class context for: " .. filename)

        unl_api.provider.request("uep.get_class_context", { 
            class_name = filename,
            on_complete = function(success, context)
                if is_cancelled then 
                    logger.get().debug("Request cancelled.")
                    return 
                end
                
                local co = coroutine.create(function()
                    local nodes = {}
                    local registry = IDRegistry.new()
                    local render_seen_ids = {}

                    if success and context then
                        logger.get().debug("UEP returned context. Building async tree...")
                        nodes = SymbolParser.build_tree_from_context_async(context, registry, render_seen_ids)
                    end

                    if not nodes or #nodes == 0 then
                        logger.get().debug("Nodes empty. Running fallback parse for: " .. buf_name_delayed)
                        nodes = SymbolParser.build_tree_fallback(buf_name_delayed, registry, render_seen_ids)
                    else
                        logger.get().debug("Async tree build success. Nodes count: " .. #nodes)
                    end
                    
                    state.class_name = filename
                    state.last_bufnr = current_buf_delayed
                    ctx_symbols.set(state)

                    runtime_state.tree_ref = tree_instance
                    runtime_state.ticks[current_buf_delayed] = current_tick

                    if not is_cancelled then
                        logger.get().debug("Scheduling render update for " .. filename)
                        vim.schedule(function()
                            if is_cancelled then return end
                            if not tree_instance then return end
                            
                            local render_ok, render_err = pcall(function()
                                tree_instance:set_nodes(nodes)
                                tree_instance:render()
                            end)
                            
                            if not render_ok then
                                logger.get().error("Render failed: " .. tostring(render_err))
                            else
                                logger.get().debug("Render complete")
                            end
                            
                            if target_winid and vim.api.nvim_win_is_valid(target_winid) then
                                local icon = "󰌗"
                                if ft == "cpp" then icon = "" elseif ft == "h" then icon = "" end
                                pcall(vim.api.nvim_win_set_option, target_winid, "winbar", string.format("%%#UNXGitFunction# %s %s", icon, filename))
                            end
                            
                            if ctx_symbols.get().class_name == filename then
                                 runtime_state.cancel_func = nil
                            end
                        end)
                    end
                end)

                local function pump()
                    if is_cancelled then return end
                    
                    if coroutine.status(co) == "suspended" then
                        local ok, err = coroutine.resume(co)
                        if not ok then
                            logger.get().error("Coroutine failed: " .. tostring(err))
                            return
                        end
                        if coroutine.status(co) ~= "dead" then
                            vim.schedule(pump)
                        end
                    end
                end

                pump()
            end
        })
    end))
end

function M.on_node_action(tree_instance, split_instance, other_split_instance)
    local node = tree_instance:get_node()
    if not node then return end
    
    if node.kind == "Class" or node.kind == "UClass" or node.kind == "Struct" or node.kind == "UStruct" then
        return
    end

    -- ★★★ 修正: 親クラス(BaseClass)の遅延読み込みハンドリング ★★★
    if node.kind == "BaseClass" and node.lazy_load then
        if node:is_expanded() then
            node:collapse()
        else
            -- まだ読み込まれていない場合は解析して子ノードを追加
            if not node:has_children() then
                 logger.get().debug("Lazy loading base class: " .. node.text)
                 
                 -- 非同期で実行しても良いが、UI操作へのレスポンスなのでここでは同期的に解析を行う
                 -- (ファイルサイズが巨大でなければ一瞬で終わるはず)
                 local children = SymbolParser.parse_and_get_children(node.file_path, node.text)
                 
                 if children and #children > 0 then
                     tree_instance:set_nodes(children, node:get_id())
                     node.lazy_load = false -- 読み込み完了
                 else
                     vim.notify("No symbols found in base class.", vim.log.levels.INFO)
                 end
            end
            node:expand()
        end
        tree_instance:render()
        return
    end
    -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★

    if node:has_children() then
        if node:is_expanded() then node:collapse() else node:expand() end
        tree_instance:render()
    elseif node.line then
        if node.file_path then
             runtime_state.ignore_next_update = true
             
             unl_open.safe({
                file_path = node.file_path,
                open_cmd = "edit",
                plugin_name = "UNX",
                split_cmd = "vertical botright split",
            })
            vim.api.nvim_win_set_cursor(0, { node.line, 0 })
            vim.cmd("normal! zz")
        end
    end
end

return M

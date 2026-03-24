local Tree = require("nui.tree")
local Line = require("nui.line")
local unl_api = require("UNL.api")
local unl_open = require("UNL.buf.open")
local ctx_uproject = require("UNX.context.uproject")
local logger = require("UNX.logger")

local M = {}

local active_tree = nil
local is_loading = false
local last_result = nil -- キャッシュ用

-- =====================================================================
-- 1. Helper Functions (Conversion from Server Data)
-- =====================================================================

local function convert_server_data_to_nodes(platforms, filter)
    local root_children = {}
    
    if not platforms or type(platforms) ~= "table" then return root_children end

    local filter_lower = filter and filter ~= "" and filter:lower() or nil

    for _, p in ipairs(platforms) do
        local platform_children = {}
        local platform_match = filter_lower and p.name:lower():find(filter_lower, 1, true)

        for _, s in ipairs(p.sections or {}) do
            local section_children = {}
            local section_match = filter_lower and s.name:lower():find(filter_lower, 1, true)

            for _, param in ipairs(s.parameters or {}) do
                local param_match = filter_lower and param.key:lower():find(filter_lower, 1, true)
                
                local history_nodes = {}
                local any_history_match = false
                
                for i, h in ipairs(param.history or {}) do
                    local h_text = string.format("%s %s [%s]", h.op == "" and "=" or h.op, h.value, h.file)
                    local h_match = filter_lower and h_text:lower():find(filter_lower, 1, true)
                    
                    if h_match then any_history_match = true end
                    
                    -- ヒットしたか、親がヒットしている場合に含める
                    if not filter_lower or h_match or param_match or section_match or platform_match then
                        table.insert(history_nodes, Tree.Node({
                            text = h_text,
                            id = string.format("hist_%s_%s_%s_%d_%d", p.name, s.name, param.key, h.line, i),
                            type = "history",
                            extra = { filepath = h.full_path, line = h.line, op = h.op }
                        }))
                    end
                end
                
                -- パラメータが一致するか、履歴のいずれかが一致するか、セクション/プラットフォームが一致する場合に含める
                if not filter_lower or param_match or any_history_match or section_match or platform_match then
                    table.insert(section_children, Tree.Node({
                        text = param.key, 
                        id = string.format("param_%s_%s_%s", p.name, s.name, param.key),
                        type = "parameter", 
                        extra = { final_value = param.value }
                    }, history_nodes))
                end
            end

            -- セクション内に子があるか、セクション名自体が一致する場合に含める
            if not filter_lower or #section_children > 0 or section_match or platform_match then
                table.insert(platform_children, Tree.Node({
                    text = s.name, 
                    id = string.format("section_%s_%s", p.name, s.name), 
                    type = "section"
                }, section_children))
            end
        end

        -- プラットフォーム内に子があるか、プラットフォーム名自体が一致する場合に含める
        if not filter_lower or #platform_children > 0 or platform_match then
            table.insert(root_children, Tree.Node({
                text = p.name, 
                id = "target_" .. p.name, 
                type = p.is_profile and "profile" or "platform"
            }, platform_children))
        end
    end
    
    return root_children
end

-- =====================================================================
-- 2. View Interface
-- =====================================================================

local function get_platform_icon(name)
    local lower = name:lower()
    if lower:find("windows") then return " " end
    if lower:find("mac") or lower:find("ios") or lower:find("tvos") or lower:find("apple") then return " " end
    if lower:find("android") then return " " end
    if lower:find("linux") or lower:find("unix") then return " " end
    if lower:find("default") then return " " end
    return " " 
end

local function prepare_node(node)
    local line = Line()
    line:append(string.rep("  ", node:get_depth() - 1))
    local icon = " "
    local icon_hl = "Normal"
    if node:has_children() then
        icon = node:is_expanded() and " " or " "
        icon_hl = "NonText"
    end

    if node.type == "root" then
        line:append(icon, icon_hl); line:append(" ", "Directory"); line:append(node.text, "Title")
    elseif node.type == "info" then
        line:append("  "); line:append("󰋽 ", "DiagnosticInfo"); line:append(node.text, "Comment")
    elseif node.type == "platform" then
        line:append(icon, icon_hl); line:append(get_platform_icon(node.text), "Type"); line:append(node.text, "Type")
    elseif node.type == "profile" then
        line:append(icon, icon_hl); line:append(" ", "Special"); line:append(node.text, "Special")
    elseif node.type == "section" then
        line:append(icon, icon_hl); line:append(" ", "Special"); line:append(node.text, "Special")
    elseif node.type == "parameter" then
        line:append(icon, icon_hl); line:append(" ", "Function"); line:append(node.text, "Identifier")
        if node.extra and node.extra.final_value then
            line:append(" = ", "Operator"); line:append(node.extra.final_value, "String")
        end
    elseif node.type == "history" then
        line:append("  ↳ ", "Comment") 
        local val_part, file_part = node.text:match("^(.*)%s(%[.*%])$")
        if val_part and file_part then
            line:append(val_part, "String"); line:append(" ", "Normal"); line:append(file_part, "Comment")
        else line:append(node.text, "Comment") end
    else line:append(icon .. node.text, "Normal") end
    return line
end

function M.start_filter(tree)
    local ctx = ctx_uproject.get()
    local current_filter = ctx.config_filter_text or ""
    
    vim.ui.input({ 
        prompt = "Filter Config (/ to clear): ", 
        default = current_filter 
    }, function(input)
        if input == nil then return end 
        if input == "/" then input = "" end
        
        ctx.config_filter_text = input
        ctx_uproject.set(ctx)
        
        M.render(tree)
        
        if input ~= "" then
            logger.get().info("Config filter applied: " .. input)
        else
            logger.get().info("Config filter cleared.")
        end
    end)
end

function M.clear_filter(tree)
    local ctx = ctx_uproject.get()
    if not ctx.config_filter_text or ctx.config_filter_text == "" then return end
    
    ctx.config_filter_text = ""
    ctx_uproject.set(ctx)
    M.render(tree)
    logger.get().info("Config filter cleared.")
end

function M.apply_keymaps(bufnr, tree)
    local map_opts = { buffer = bufnr, noremap = true, silent = true }
    vim.keymap.set("n", "/", function() M.start_filter(tree) end, map_opts)
end

function M.create(bufnr)
    active_tree = Tree({ bufnr = bufnr, nodes = {}, prepare_node = prepare_node })
    M.apply_keymaps(bufnr, active_tree)
    return active_tree
end

function M.render(tree_instance)
    if not tree_instance then tree_instance = active_tree end
    if not tree_instance then return end
    
    if is_loading then return end

    local ctx = ctx_uproject.get()
    if not ctx.project_root then
        tree_instance:set_nodes({ Tree.Node({ text = "No project root.", kind = "Info" }) })
        tree_instance:render(); return
    end

    local filter = ctx.config_filter_text

    local function apply_result(result)
        local nodes = convert_server_data_to_nodes(result, filter)
        local root_nodes = {}
        
        if filter and filter ~= "" then
            table.insert(root_nodes, Tree.Node({
                text = "Search: " .. filter .. " (Press / to clear)", id = "config_filter_header", type = "info"
            }))
        end

        local config_root = Tree.Node({
            text = "Config Explorer (Remote)", id = "config_logical_root", type = "root"
        }, nodes)
        config_root:expand()
        table.insert(root_nodes, config_root)
        
        tree_instance:set_nodes(root_nodes)
        tree_instance:render()
    end

    -- キャッシュがあれば再利用（フィルタリングのみの場合）
    if last_result then
        apply_result(last_result)
        return
    end

    is_loading = true
    tree_instance:set_nodes({ Tree.Node({ text = " 󱑮 Loading Config Data from Server...", type = "info" }) })
    tree_instance:render()

    unl_api.db.query("GetConfigData", { 
        engine_root = ctx.engine_root 
    }, function(result, err)
        is_loading = false
        if err or not result then
            tree_instance:set_nodes({ Tree.Node({ text = "Error: " .. tostring(err or "No result"), type = "error" }) })
            tree_instance:render()
            return
        end

        last_result = result
        apply_result(result)
    end)
end

function M.refresh(tree_instance)
    last_result = nil -- 明示的なリフレッシュ時はキャッシュをクリア
    M.render(tree_instance)
end

function M.on_node_action(tree_instance)
    local node = tree_instance:get_node()
    if not node then return end
    if node:has_children() then
        if node:is_expanded() then node:collapse() else node:expand() end
        tree_instance:render(); return
    end
    if node.type == "history" and node.extra and node.extra.filepath then
        local filepath = node.extra.filepath
        local line = node.extra.line or 1
        unl_open.safe({ file_path = filepath, open_cmd = "edit", plugin_name = "UNX", split_cmd = "vsplit" })
        vim.schedule(function()
            pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
            vim.cmd("normal! zz")
        end)
    end
end

return M

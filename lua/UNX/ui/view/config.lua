local Tree = require("nui.tree")
local Line = require("nui.line")
local unl_api = require("UNL.api")
local unl_open = require("UNL.buf.open")
local ctx_uproject = require("UNX.context.uproject")

local M = {}

local active_tree = nil
local is_loading = false

-- =====================================================================
-- 1. Helper Functions (Conversion from Server Data)
-- =====================================================================

local function convert_server_data_to_nodes(platforms)
    local root_children = {}
    
    if not platforms or type(platforms) ~= "table" then return root_children end

    for _, p in ipairs(platforms) do
        local platform_children = {}
        for _, s in ipairs(p.sections or {}) do
            local section_children = {}
            for _, param in ipairs(s.parameters or {}) do
                local history_nodes = {}
                for i, h in ipairs(param.history or {}) do
                    table.insert(history_nodes, Tree.Node({
                        text = string.format("%s %s [%s]", h.op == "" and "=" or h.op, h.value, h.file),
                        id = string.format("hist_%s_%s_%s_%d_%d", p.name, s.name, param.key, h.line, i),
                        type = "history",
                        extra = { filepath = h.full_path, line = h.line, op = h.op }
                    }))
                end
                table.insert(section_children, Tree.Node({
                    text = param.key, 
                    id = string.format("param_%s_%s_%s", p.name, s.name, param.key),
                    type = "parameter", 
                    extra = { final_value = param.value }
                }, history_nodes))
            end
            table.insert(platform_children, Tree.Node({
                text = s.name, 
                id = string.format("section_%s_%s", p.name, s.name), 
                type = "section"
            }, section_children))
        end
        table.insert(root_children, Tree.Node({
            text = p.name, 
            id = "target_" .. p.name, 
            type = p.is_profile and "profile" or "platform"
        }, platform_children))
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

function M.create(bufnr)
    active_tree = Tree({ bufnr = bufnr, nodes = {}, prepare_node = prepare_node })
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

    is_loading = true
    tree_instance:set_nodes({ Tree.Node({ text = " 󱑮 Loading Config Data from Server...", type = "info" }) })
    tree_instance:render()

    -- コールバック引数は (result, err) の順序
    unl_api.db.query("GetConfigData", { 
        engine_root = ctx.engine_root 
    }, function(result, err)
        is_loading = false
        if err or not result then
            tree_instance:set_nodes({ Tree.Node({ text = "Error: " .. tostring(err or "No result"), type = "error" }) })
            tree_instance:render()
            return
        end

        local nodes = convert_server_data_to_nodes(result)
        local root_node = Tree.Node({
            text = "Config Explorer (Remote)", id = "config_logical_root", type = "root"
        }, nodes)
        root_node:expand()
        
        tree_instance:set_nodes({ root_node })
        tree_instance:render()
    end)
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

-- lua/UNX/ui/view/config.lua

local Tree = require("nui.tree")
local Line = require("nui.line")
local unl_api = require("UNL.api")
local uep_log = require("UEP.logger").get()
local unl_open = require("UNL.buf.open")

local M = {}

local active_tree = nil
local last_payload = nil

-- ★新規: プラットフォーム用アイコン取得関数
local function get_platform_icon(name)
    local lower = name:lower()
    if lower:find("windows") then return " " end
    if lower:find("mac") or lower:find("ios") or lower:find("tvos") then return " " end
    if lower:find("android") then return " " end
    if lower:find("linux") or lower:find("unix") then return " " end
    
    -- ★追加
    if lower:find("apple") then return " " end
    
    if lower:find("default") then return " " end
    return " " 
end

local function prepare_node(node)
    local line = Line()
    line:append(string.rep("  ", node:get_depth() - 1))

    local icon = " "
    local icon_hl = "Normal"
    local name_hl = "Normal"
    local extra = node.extra or {}

    if node:has_children() then
        icon = node:is_expanded() and " " or " "
        icon_hl = "NonText"
    end

    if node.type == "root" then
        line:append(icon, icon_hl)
        line:append(" ", "Directory")
        line:append(node.text, "Title")

    elseif node.type == "platform" then
        line:append(icon, icon_hl)
        -- ★修正: プラットフォーム名に応じたアイコンを表示
        local p_icon = get_platform_icon(node.text)
        line:append(p_icon, "Type")
        line:append(node.text, "Type")

    elseif node.type == "profile" then -- ★ 追加
        line:append(icon, icon_hl)
        line:append(" ", "Special") -- デバイスプロファイル用アイコン (画像/デバイスっぽいもの)
        line:append(node.text, "Special")

    elseif node.type == "section" then
        line:append(icon, icon_hl)
        line:append(" ", "Special")
        line:append(node.text, "Special")

    elseif node.type == "parameter" then
        line:append(icon, icon_hl)
        line:append(" ", "Function")
        line:append(node.text, "Identifier")
        if extra.final_value then
            line:append(" = ", "Operator")
            line:append(extra.final_value, "String")
        end

    elseif node.type == "history" then
        line:append("  ↳ ", "Comment") 
        local val_part, file_part = node.text:match("^(.*)%s(%[.*%])$")
        if val_part and file_part then
            line:append(val_part, "String")
            line:append(" ", "Normal")
            line:append(file_part, "Comment")
        else
            line:append(node.text, "Comment")
        end
    else
        line:append(icon .. node.text, "Normal")
    end
    
    return line
end

-- (convert_uep_to_nui, create, render, on_node_action は変更なし)
-- 以下省略 (前回のコードと同じ)
local function convert_uep_to_nui(uep_node)
    local children = nil
    if uep_node.children and #uep_node.children > 0 then
        children = {}
        for _, child in ipairs(uep_node.children) do
            table.insert(children, convert_uep_to_nui(child))
        end
    end
    local nui_node = Tree.Node({
        text = uep_node.name, id = uep_node.id, path = uep_node.path,
        type = uep_node.type, loaded = uep_node.loaded,
        _has_children = uep_node.loaded == false or (children and #children > 0),
        extra = uep_node.extra, 
    }, children)
    if uep_node.type == "root" or uep_node.type == "platform" then nui_node:expand() end
    return nui_node
end

function M.create(bufnr)
    local tree = Tree({ bufnr = bufnr, nodes = {}, prepare_node = prepare_node })
    active_tree = tree
    return tree
end

function M.render(tree_instance)
    if not tree_instance then tree_instance = active_tree end
    if not tree_instance then return end
    local payload = last_payload or {}
    local success, result = unl_api.provider.request("uep.get_config_tree_model", {
        capability = "uep.get_config_tree_model", scope = payload.scope, logger_name = "UNX",
    })
    if success and result and result[1] then
        local root_node = convert_uep_to_nui(result[1])
        tree_instance:set_nodes({ root_node })
    else
        tree_instance:set_nodes({ Tree.Node({ text = "No config data.", kind = "Info" }) })
    end
    tree_instance:render()
end

function M.on_node_action(tree_instance, split_instance, other_split_instance)
    local node = tree_instance:get_node()
    if not node then return end
    if node:has_children() then
        if node:is_expanded() then node:collapse() else node:expand() end
        tree_instance:render()
        return
    end
    if node.type == "history" and node.extra and node.extra.filepath then
        local filepath = node.extra.filepath
        local line = node.extra.line or 1
        vim.notify("Jumping to: " .. filepath, vim.log.levels.INFO)
        unl_open.safe({ file_path = filepath, open_cmd = "edit", plugin_name = "UNX", split_cmd = "vsplit" })
        vim.schedule(function()
            pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
            vim.cmd("normal! zz")
        end)
    end
end

return M

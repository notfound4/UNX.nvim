-- lua/UNX/ui/view/symbols.lua
local Tree = require("nui.tree")
local Line = require("nui.line")
local unl_api = require("UNL.api")
local Query = require("UNX.ui.view.query")

local M = {}
local config = {}

-- 非同期リクエスト管理用
local current_request_token = 0

-- ======================================================
-- 1. DEBUG LOGGING
-- ======================================================
local function debug_log(fmt, ...)
    -- local msg = string.format("[UNX-SYM] " .. fmt, ...)
    -- vim.api.nvim_command("echomsg '" .. msg:gsub("'", "''") .. "'")
end

-- (2. DATA STRUCTURE HELPERS は変更なし。そのままコピーしてください)
-- ... (new_class_data, new_global_data, merge_class_data, build_class_node, build_nui_nodes) ...
-- 前回のコードと同じ内容を維持してください

-- (以下、前回のコードからヘルパー関数定義を省略しています。実際にはここに記述してください)
-- ※ 重要なのは M.update 関数です

-- ... (省略されたヘルパー関数群: new_class_data, merge_class_data 等) ...
-- ★ここには前回のコードの「DATA STRUCTURE HELPERS」セクションが入ります

local function new_class_data(text, kind, line, id, s_col)
    local default_access = (kind == "Struct" or kind == "UStruct") and "public" or "private"
    return {
        text = text, kind = kind, line = line, id = id, s_col = s_col,
        base_class = nil,
        current_access = default_access,
        methods = { public = {}, protected = {}, private = {}, impl = {} },
        fields  = { public = {}, protected = {}, private = {}, impl = {} },
    }
end

local function new_global_data()
    return { methods = {}, fields = {} }
end

local function merge_class_data(dest, src)
    if not src then return end
    for _, access in ipairs({"public", "protected", "private", "impl"}) do
        for _, item in ipairs(src.methods[access]) do
            item.kind = "Implementation"
            table.insert(dest.methods["impl"], item)
        end
        for _, item in ipairs(src.fields[access]) do
            table.insert(dest.fields["impl"], item)
        end
    end
end

local function build_class_node(class_data)
    local children = {}
    
    -- Members
    local field_group_children = {}
    for _, access in ipairs({"public", "protected", "private", "impl"}) do
        local items = class_data.fields[access]
        if items and #items > 0 then
            if access == "impl" then
                for _, item in ipairs(items) do table.insert(field_group_children, Tree.Node(item)) end
            else
                local access_node_children = {}
                for _, item in ipairs(items) do table.insert(access_node_children, Tree.Node(item)) end
                local access_node = Tree.Node({ text = access .. ":", kind = "Access", id = class_data.id .. "_fields_" .. access }, access_node_children)
                access_node:expand()
                table.insert(field_group_children, access_node)
            end
        end
    end
    if #field_group_children > 0 then
        local group_node = Tree.Node({ text = "Members", kind = "GroupFields", id = class_data.id .. "_group_fields" }, field_group_children)
        table.insert(children, group_node)
    end

    -- Functions
    local func_group_children = {}
    for _, access in ipairs({"public", "protected", "private", "impl"}) do
        local items = class_data.methods[access]
        if items and #items > 0 then
            if access == "impl" then
                for _, item in ipairs(items) do table.insert(func_group_children, Tree.Node(item)) end
            else
                local access_node_children = {}
                for _, item in ipairs(items) do table.insert(access_node_children, Tree.Node(item)) end
                local access_node = Tree.Node({ text = access .. ":", kind = "Access", id = class_data.id .. "_funcs_" .. access }, access_node_children)
                access_node:expand()
                table.insert(func_group_children, access_node)
            end
        end
    end

    if #func_group_children > 0 then
        local group_node = Tree.Node({ text = "Functions", kind = "GroupMethods", id = class_data.id .. "_group_funcs" }, func_group_children)
        group_node:expand()
        table.insert(children, group_node)
    end

    local node = Tree.Node({
        text = class_data.text, kind = class_data.kind, line = class_data.line, id = class_data.id,
        file_path = class_data.file_path
    }, children)
    
    node:expand()
    return node
end

local function build_nui_nodes(data_list)
    local nodes = {}
    for _, data in ipairs(data_list) do
        local children = nil
        if data.children and #data.children > 0 then
            children = build_nui_nodes(data.children)
        end
        local node = Tree.Node({
            text = data.text, detail = data.detail, kind = data.kind, line = data.line, id = data.id,
            file_path = data.file_path
        }, children)
        if children then node:expand() end
        table.insert(nodes, node)
    end
    return nodes
end

-- (3, 4, 5, 6. PARSING HELPERS, QUERY, CORE PARSING LOGIC は前回のコードと同じ)
-- 省略せずに記述しますが、変更はありません
local function get_node_text(node, bufnr)
    if not node then return "" end
    return vim.treesitter.get_node_text(node, bufnr)
end

local function has_child_type(node, type_name)
    local count = node:child_count()
    for i = 0, count - 1 do
        local child = node:child(i)
        if child:type() == type_name then return true end
    end
    return false
end

local function has_body(definition_node)
    local type = definition_node:type()
    if type == "class_specifier" or type == "struct_specifier" then return has_child_type(definition_node, "field_declaration_list") end
    if type == "enum_specifier" then return has_child_type(definition_node, "enumerator_list") end
    if type == "unreal_class_declaration" or type == "unreal_struct_declaration" then return has_child_type(definition_node, "field_declaration_list") end
    if type == "unreal_enum_declaration" then return has_child_type(definition_node, "enumerator_list") end
    return false
end

local function get_base_class_name(definition_node, bufnr)
    for child in definition_node:iter_children() do
        if child:type() == "base_class_clause" then
            local base = child:named_child(0)
            if base then return get_node_text(base, bufnr) end
        end
    end
    return nil
end

local function get_parameters_text(node, bufnr)
    local p = node:parent()
    local func_declarator = nil
    for _ = 1, 5 do
        if not p then break end
        if p:type() == "function_declarator" then func_declarator = p; break end
        p = p:parent()
    end
    if func_declarator then
        for child in func_declarator:iter_children() do
            if child:type() == "parameter_list" then
                local text = get_node_text(child, bufnr)
                return text:gsub("%s+", " ")
            end
        end
    end
    return "()"
end

local function is_type_reference(node)
    local parent = node:parent()
    while parent do
        local type = parent:type()
        if type == "compound_statement" or type == "field_declaration_list" then return false end
        if type == "parameter_declaration" then return true end
        if type == "function_definition" then
            if not node:type():match("declarator") then return true end
        end
        if type == "field_declaration" then
             if not node:type():match("declarator") then return true end
        end
        parent = parent:parent()
    end
    return false
end

local function parse_file_content(file_path)
    if not file_path or file_path == "" or vim.fn.filereadable(file_path) == 0 then return {}, new_global_data(), {} end
    local bufnr = vim.fn.bufadd(file_path)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
        vim.bo[bufnr].filetype = "cpp"
    end
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "cpp")
    if not ok or not parser then return {}, new_global_data(), {} end
    local tree_root = parser:parse()[1]:root()
    local query_ok, query = pcall(vim.treesitter.query.parse, "cpp", Query.cpp)
    if not query_ok then return {}, new_global_data(), {} end

    local classes_map = {}
    local classes_list = {}
    local global_data = new_global_data()
    local last_class_data = nil
    local last_class_range = { -1, -1, -1, -1 }
    local seen_ids = {}
    local file_id_prefix = vim.fn.sha256(file_path):sub(1, 8)
    local function get_unique_id(base_id)
        local full_id = file_id_prefix .. "_" .. base_id
        if not seen_ids[full_id] then seen_ids[full_id] = 1; return full_id
        else local c = seen_ids[full_id]; seen_ids[full_id] = c + 1; return string.format("%s_dup%d", full_id, c) end
    end
    local function get_or_create_class_data(name, line, s_col)
        if classes_map[name] then return classes_map[name] end
        local kind = "Class"
        local first_char = name:sub(1,1)
        if first_char == "A" or first_char == "U" then kind = "UClass" elseif first_char == "F" then kind = "UStruct" elseif first_char == "E" then kind = "UEnum" end
        local raw_id = string.format("%s_%d_%d", name, line, s_col)
        local c_data = new_class_data(name, kind, line, get_unique_id(raw_id), s_col)
        c_data.file_path = file_path
        table.insert(classes_list, c_data)
        classes_map[name] = c_data
        return c_data
    end
    local pending_impl_class = nil
    for id, node, metadata in query:iter_captures(tree_root, bufnr, 0, -1) do
        local capture_name = query.captures[id]
        if (capture_name == "class_name" or capture_name == "struct_name" or capture_name == "enum_name") and is_type_reference(node) then goto continue end
        local text = get_node_text(node, bufnr)
        local s_row, s_col, e_row, _ = node:range()
        local line_num = s_row + 1
        local definition_node = node
        while definition_node do
            local type = definition_node:type()
            if type:match("declaration") or type:match("specifier") or type:match("definition") then break end
            definition_node = definition_node:parent()
        end
        if not definition_node then definition_node = node end

        if capture_name == "class_name" or capture_name == "struct_name" or capture_name == "enum_name" then
            if not has_body(definition_node) then goto continue end
            local kind = "Class"
            if capture_name == "struct_name" then kind = "Struct" end
            if capture_name == "enum_name" then kind = "Enum" end
            local type = definition_node:type()
            if type == "unreal_class_declaration" then kind = "UClass" end
            if type == "unreal_struct_declaration" then kind = "UStruct" end
            if type == "unreal_enum_declaration" then kind = "UEnum" end
            local base_class_text = get_base_class_name(definition_node, bufnr)
            local class_data = get_or_create_class_data(text, line_num, s_col)
            class_data.kind = kind
            class_data.base_class = base_class_text
            class_data.line = line_num
            last_class_data = class_data
            last_class_range = { definition_node:range() }
        elseif capture_name == "impl_class" then pending_impl_class = text
        elseif capture_name == "access_label" then
            local access = text:gsub(":", "")
            if access == "public" or access == "protected" or access == "private" then
                if last_class_data and s_row >= last_class_range[1] and s_row <= last_class_range[3] then last_class_data.current_access = access end
            end
        elseif capture_name == "func_name" then
            local kind = "Function"
            if has_child_type(definition_node, "ufunction_macro") then kind = "UFunction" end
            local target_class_data = last_class_data
            local access_bucket = target_class_data and target_class_data.current_access or "public"
            if pending_impl_class then
                target_class_data = get_or_create_class_data(pending_impl_class, line_num, s_col)
                access_bucket = "impl"
                if text == pending_impl_class or text == "~" .. pending_impl_class then kind = "Constructor" end
                pending_impl_class = nil
            elseif last_class_data then
                if text == last_class_data.text or text == "~" .. last_class_data.text then kind = "Constructor" end
            else target_class_data = nil end
            local params = get_parameters_text(node, bufnr)
            local raw_id = string.format("%s_%d_%d", text, line_num, s_col)
            local func_item = { text = text, detail = params, kind = kind, line = line_num, id = get_unique_id(raw_id), file_path = file_path }
            if target_class_data then table.insert(target_class_data.methods[access_bucket], func_item) else table.insert(global_data.methods, func_item) end
        elseif capture_name == "field_name" then
            local kind = "Field"
            if has_child_type(definition_node, "uproperty_macro") then kind = "UProperty" end
            local raw_id = string.format("%s_%d_%d", text, line_num, s_col)
            local field_item = { text = text, kind = kind, line = line_num, id = get_unique_id(raw_id), file_path = file_path }
            if last_class_data and s_row >= last_class_range[1] and s_row <= last_class_range[3] then
                local access = last_class_data.current_access
                table.insert(last_class_data.fields[access], field_item)
            else table.insert(global_data.fields, field_item) end
        end
        ::continue::
    end
    return classes_map, global_data, classes_list
end

-- ======================================================
-- 7. BUILDERS
-- ======================================================

local function build_tree_from_context(context)
    local root_nodes = {}
    if context.parents then
        for i = #context.parents, 1, -1 do
            local parent_info = context.parents[i]
            local p_map, _, _ = parse_file_content(parent_info.header)
            local p_data = p_map[parent_info.name]
            local p_node
            if p_data then
                p_node = build_class_node(p_data)
                p_node.kind = "BaseClass"
            else
                p_node = Tree.Node({ text = parent_info.name, kind = "BaseClass", id = "base_" .. parent_info.name, file_path = parent_info.header })
            end
            p_node:collapse()
            table.insert(root_nodes, p_node)
        end
    end

    local current_info = context.current
    if not current_info then return root_nodes end
    local h_map, _, h_list = parse_file_content(current_info.header)
    local cpp_map, _, cpp_list = parse_file_content(current_info.cpp)
    local main_class_name = current_info.name
    local main_class_data = h_map[main_class_name]

    if main_class_data then
        if cpp_map[main_class_name] then merge_class_data(main_class_data, cpp_map[main_class_name]) end
        local main_node = build_class_node(main_class_data)
        main_node:expand()
        table.insert(root_nodes, main_node)
    else
        for _, class_data in ipairs(h_list) do
            if cpp_map[class_data.text] then merge_class_data(class_data, cpp_map[class_data.text]) end
            local node = build_class_node(class_data)
            node:expand()
            table.insert(root_nodes, node)
        end
    end
    return root_nodes
end

-- ======================================================
-- 8. RENDERER & API
-- ======================================================

local function prepare_node(node)
    local line = Line()
    line:append(string.rep("  ", node:get_depth() - 1))
    local icon, icon_hl, text_hl = " ", "Normal", "UNXFileName"
    if node.kind == "UClass" then icon = "UE "; icon_hl = "UNXGitAdded"; text_hl = "Type"
    elseif node.kind == "UStruct" then icon = "US "; icon_hl = "UNXGitAdded"; text_hl = "Type"
    elseif node.kind == "UEnum" then icon = "En "; icon_hl = "UNXGitAdded"; text_hl = "Type"
    elseif node.kind == "Class" then icon = "󰌗 "; icon_hl = "Type"; text_hl = "Type"
    elseif node.kind == "Struct" then icon = "󰌗 "; icon_hl = "Type"; text_hl = "Type"
    elseif node.kind == "UFunction" then icon = "UF "; icon_hl = "UNXModifiedIcon"; text_hl = "Function"
    elseif node.kind == "Function" then icon = "󰊕 "; icon_hl = "Function"
    elseif node.kind == "Constructor" then icon = " "; icon_hl = "Special"
    elseif node.kind == "UProperty" then icon = "UP "; icon_hl = "UNXDirectoryIcon"
    elseif node.kind == "Field" then icon = " "; icon_hl = "Identifier"
    elseif node.kind == "Access" then icon = " "; icon_hl = "Special"; text_hl = "Special"
    elseif node.kind == "GroupFields" then icon = " "; icon_hl = "Special"; text_hl = "Title"
    elseif node.kind == "GroupMethods" then icon = "󰊕 "; icon_hl = "Special"; text_hl = "Title"
    elseif node.kind == "BaseClass" then icon = "󰜮 "; icon_hl = "UNXGitRenamed"; text_hl = "Comment"
    elseif node.kind == "Implementation" then icon = " "; icon_hl = "Comment"; text_hl = "Comment"
    elseif node.kind == "Info" then icon = " "; icon_hl = "Comment"
    end
    line:append(icon, icon_hl)
    line:append(node.text, text_hl)
    if node.detail and node.detail ~= "" then line:append(node.detail, "Comment") end
    return line
end

function M.setup(user_config)
    config = user_config
end

function M.create(bufnr)
    return Tree({ bufnr = bufnr, nodes = {}, prepare_node = prepare_node })
end

-- ★修正: 非同期・非ブロッキングな更新処理
function M.update(tree_instance, target_winid)
    if not tree_instance then return end
    
    local current_buf = vim.api.nvim_get_current_buf()
    local buf_name = vim.api.nvim_buf_get_name(current_buf)
    if buf_name == "" then return end

    local ft = vim.bo[current_buf].filetype
    if ft == "unx-explorer" or ft == "neo-tree" or ft == "TelescopePrompt" or ft == "qf" then return end

    local filename = vim.fn.fnamemodify(buf_name, ":t:r")
    if not filename or filename == "" then return end

    -- リクエストトークンを発行して、古いリクエストの結果を無視できるようにする
    current_request_token = current_request_token + 1
    local my_token = current_request_token

    -- 非同期リクエスト (on_complete コールバックを使用)
    unl_api.provider.request("uep.get_class_context", { 
        class_name = filename,
        on_complete = function(success, context)
            -- トークンチェック: 最新のリクエストでなければ無視
            if my_token ~= current_request_token then return end
            
            -- UI更新はメインループで行う
            vim.schedule(function()
                -- ツリーがまだ有効かチェック
                if not tree_instance.bufnr or not vim.api.nvim_buf_is_valid(tree_instance.bufnr) then return end

                local nodes
                if success and context then
                    nodes = build_tree_from_context(context)
                else
                    -- フォールバック (ローカル解析)
                    -- ここも重いなら非同期化すべきだが、とりあえず現状維持
                    local map, global, list = parse_file_content(buf_name)
                    nodes = {}
                    for _, cdata in ipairs(list) do
                        local node = build_class_node(cdata)
                        node:expand()
                        table.insert(nodes, node)
                    end
                    if #global.methods > 0 or #global.fields > 0 then
                        local g_children = {}
                        for _, item in ipairs(global.methods) do table.insert(g_children, Tree.Node(item)) end
                        for _, item in ipairs(global.fields) do table.insert(g_children, Tree.Node(item)) end
                        local g_node = Tree.Node({ text = "Global", kind = "Info", id = "global_scope" }, g_children)
                        table.insert(nodes, g_node)
                    end
                end
                
                tree_instance:set_nodes(nodes)
                tree_instance:render()
                
                if target_winid and vim.api.nvim_win_is_valid(target_winid) then
                    local icon = "󰌗"
                    if ft == "cpp" then icon = "" elseif ft == "h" then icon = "" end
                    pcall(vim.api.nvim_win_set_option, target_winid, "winbar", string.format("%%#UNXGitFunction# %s %s", icon, filename))
                end
            end)
        end
    })
end

function M.on_node_action(tree_instance, split_instance, other_split_instance)
    local node = tree_instance:get_node()
    if not node then return end
    
    if node.kind == "Class" or node.kind == "UClass" or node.kind == "Struct" or node.kind == "UStruct" then
        -- show_action_menu(node, split_instance) -- メニュー機能は削除済み
        return
    end

    if node:has_children() then
        if node:is_expanded() then node:collapse() else node:expand() end
        tree_instance:render()
    elseif node.line then
        local wins = vim.api.nvim_list_wins()
        for _, w in ipairs(wins) do
            if w ~= split_instance.winid and (not other_split_instance or w ~= other_split_instance.winid) then
                vim.api.nvim_set_current_win(w)
                if node.file_path then
                    vim.cmd("edit " .. vim.fn.fnameescape(node.file_path))
                end
                vim.api.nvim_win_set_cursor(w, { node.line, 0 })
                vim.cmd("normal! zz")
                break
            end
        end
    end
end

return M

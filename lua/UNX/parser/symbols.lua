-- lua/UNX/parser/symbols.lua
local Query = require("UNX.ui.view.query")
local IDRegistry = require("UNX.common.id_registry")
local logger = require("UNX.logger")
local Tree = require("nui.tree")
local unl_path = require("UNL.path") -- unl_path を追加

local M = {}

-- ======================================================
-- 2. DATA STRUCTURE HELPERS
-- ======================================================
local function new_class_data(text, kind, line, id, file_path)
    local default_access = (kind == "Struct" or kind == "UStruct") and "public" or "private"
    return {
        text = text, kind = kind, line = line, id = id, file_path = file_path,
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
            local item_copy = vim.tbl_extend("keep", {}, item)
            item_copy.kind = "Implementation"
            table.insert(dest.methods["impl"], item_copy)
        end
        for _, item in ipairs(src.fields[access]) do
            local item_copy = vim.tbl_extend("keep", {}, item)
            table.insert(dest.fields["impl"], item_copy)
        end
    end
end

local function safe_node_id(id, seen_ids)
    if not id then return "unknown_id_" .. vim.loop.hrtime() end
    if not seen_ids[id] then
        seen_ids[id] = true
        return id
    else
        local count = 1
        local new_id = id .. "_render_dup" .. count
        while seen_ids[new_id] do
            count = count + 1
            new_id = id .. "_render_dup" .. count
        end
        seen_ids[new_id] = true
        return new_id
    end
end

local function build_class_node(class_data, registry, render_seen_ids)
    local children = {}
    
    local function make_group_id(suffix)
        local raw_id = registry:get(class_data.id .. suffix)
        return safe_node_id(raw_id, render_seen_ids)
    end
    
    local function make_item_node(item)
        local unique_id = safe_node_id(item.id, render_seen_ids)
        local node_opts = vim.tbl_extend("force", item, { id = unique_id })
        return Tree.Node(node_opts)
    end

    local field_group_children = {}
    for _, access in ipairs({"public", "protected", "private", "impl"}) do
        local items = class_data.fields[access]
        if items and #items > 0 then
            if access == "impl" then
                for _, item in ipairs(items) do table.insert(field_group_children, make_item_node(item)) end
            else
                local access_node_children = {}
                for _, item in ipairs(items) do table.insert(access_node_children, make_item_node(item)) end
                
                local access_node = Tree.Node({ 
                    text = access .. ":", 
                    kind = "Access", 
                    id = make_group_id("_f_" .. access) 
                }, access_node_children)
                
                access_node:expand()
                table.insert(field_group_children, access_node)
            end
        end
    end
    
    if #field_group_children > 0 then
        local group_node = Tree.Node({ 
            text = "Members", 
            kind = "GroupFields", 
            id = make_group_id("_group_fields") 
        }, field_group_children)
        table.insert(children, group_node)
    end

    local func_group_children = {}
    for _, access in ipairs({"public", "protected", "private"}) do
        local items = class_data.methods[access]
        if items and #items > 0 then
            local access_node_children = {}
            for _, item in ipairs(items) do table.insert(access_node_children, make_item_node(item)) end
            
            local access_node = Tree.Node({ 
                text = access .. ":", 
                kind = "Access", 
                id = make_group_id("_m_" .. access) 
            }, access_node_children)
            
            access_node:expand()
            table.insert(func_group_children, access_node)
        end
    end
    
    local impl_items = class_data.methods["impl"]
    if impl_items and #impl_items > 0 then
        local impl_children = {}
        for _, item in ipairs(impl_items) do table.insert(impl_children, make_item_node(item)) end
        
        local impl_node = Tree.Node({ 
            text = "Implementations (.cpp)", 
            kind = "Access", 
            id = make_group_id("_impls_group") 
        }, impl_children)
        
        table.insert(func_group_children, impl_node)
    end

    if #func_group_children > 0 then
        local group_node = Tree.Node({ 
            text = "Functions", 
            kind = "GroupMethods", 
            id = make_group_id("_group_funcs") 
        }, func_group_children)
        group_node:expand()
        table.insert(children, group_node)
    end

    local class_node_id = safe_node_id(class_data.id, render_seen_ids)
    local node = Tree.Node({
        text = class_data.text, kind = class_data.kind, line = class_data.line, id = class_node_id,
        file_path = class_data.file_path
    }, children)
    
    node:expand()
    return node
end

-- ======================================================
-- 3. PARSING HELPERS
-- ======================================================
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
    if type == "class_specifier" or type == "struct_specifier" then
        return has_child_type(definition_node, "field_declaration_list")
    end
    if type == "enum_specifier" then
        return has_child_type(definition_node, "enumerator_list")
    end
    if type == "unreal_class_declaration" or type == "unreal_struct_declaration" then
        return has_child_type(definition_node, "field_declaration_list")
    end
    if type == "unreal_enum_declaration" then
        return has_child_type(definition_node, "enumerator_list")
    end
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
        if p:type() == "function_declarator" then
            func_declarator = p
            break
        end
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

-- ======================================================
-- 4. CORE PARSING LOGIC
-- ======================================================
local function parse_file_content(file_path, registry)
    if not file_path or file_path == "" or vim.fn.filereadable(file_path) == 0 then 
        return {}, new_global_data(), {}
    end
    
    local bufnr = vim.fn.bufadd(file_path)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
        vim.bo[bufnr].filetype = "cpp"
    end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "cpp")
    if not ok or not parser then 
        logger.get().debug("Failed to get parser for " .. file_path)
        return {}, new_global_data(), {} 
    end

    local tree_root = parser:parse()[1]:root()
    local query_ok, query = pcall(vim.treesitter.query.parse, "cpp", Query.cpp)
    if not query_ok then return {}, new_global_data(), {} end

    local classes_map = {}
    local classes_list = {}
    local global_data = new_global_data()
    
    local last_class_data = nil
    local last_class_range = { -1, -1, -1, -1 }
    
    local file_hash = IDRegistry.get_file_hash(file_path)
    
    local function generate_id(name, line, col)
        local raw = string.format("%s_%s_%d_%d", file_hash, name, line, col)
        return registry:get(raw)
    end
    
    local function get_or_create_class_data(name, line, s_col)
        if classes_map[name] then return classes_map[name] end
        
        local kind = "Class"
        local first_char = name:sub(1,1)
        if first_char == "A" or first_char == "U" then kind = "UClass"
        elseif first_char == "F" then kind = "UStruct"
        elseif first_char == "E" then kind = "UEnum" end

        local id = generate_id(name, line, s_col)
        local c_data = new_class_data(name, kind, line, id, file_path)
        
        table.insert(classes_list, c_data)
        classes_map[name] = c_data
        return c_data
    end

    local pending_impl_class = nil

    for id, node, metadata in query:iter_captures(tree_root, bufnr, 0, -1) do
        local capture_name = query.captures[id]
        
        if (capture_name == "class_name" or capture_name == "struct_name" or capture_name == "enum_name") and is_type_reference(node) then
            goto continue
        end

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

        elseif capture_name == "impl_class" then
            pending_impl_class = text
            
        elseif capture_name == "access_label" then
            local access = text:gsub(":", "")
            if access == "public" or access == "protected" or access == "private" then
                if last_class_data and s_row >= last_class_range[1] and s_row <= last_class_range[3] then
                    last_class_data.current_access = access
                end
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
            else
                target_class_data = nil
            end
            
            local params = get_parameters_text(node, bufnr)
            local func_item = {
                text = text, detail = params, kind = kind, line = line_num,
                id = generate_id(text .. "_func", line_num, s_col),
                file_path = file_path
            }

            if target_class_data then
                table.insert(target_class_data.methods[access_bucket], func_item)
            else
                table.insert(global_data.methods, func_item)
            end

        elseif capture_name == "field_name" then
            local kind = "Field"
            if has_child_type(definition_node, "uproperty_macro") then kind = "UProperty" end
            
            local field_item = {
                text = text, kind = kind, line = line_num,
                id = generate_id(text .. "_field", line_num, s_col),
                file_path = file_path
            }
            
            if last_class_data and s_row >= last_class_range[1] and s_row <= last_class_range[3] then
                local access = last_class_data.current_access
                table.insert(last_class_data.fields[access], field_item)
            else
                table.insert(global_data.fields, field_item)
            end
        end
        ::continue::
    end
    
    return classes_map, global_data, classes_list
end

-- ======================================================
-- 5. BUILDERS (Async / Coroutine)
-- ======================================================
local function build_tree_from_context_async(context, registry, render_seen_ids)
    local root_nodes = {}
    
    if context.parents then
        for i = #context.parents, 1, -1 do
            coroutine.yield()
            local parent_info = context.parents[i]
            if parent_info.header then
                local p_map, _, _ = parse_file_content(parent_info.header, registry)
                local p_data = p_map[parent_info.name]
                local p_node
                if p_data then
                    p_node = build_class_node(p_data, registry, render_seen_ids)
                    p_node.kind = "BaseClass"
                else
                    local raw_id = registry:get("base_" .. parent_info.name .. "_" .. i)
                    local safe_id = safe_node_id(raw_id, render_seen_ids)
                    p_node = Tree.Node({ text = parent_info.name, kind = "BaseClass", id = safe_id, file_path = parent_info.header })
                end
                p_node:collapse()
                table.insert(root_nodes, p_node)
            end
        end
    end

    local current_info = context.current
    if not current_info or not current_info.header then 
        logger.get().debug("build_tree: current_info or header is nil")
        return root_nodes 
    end

    coroutine.yield()
    local h_map, _, h_list = parse_file_content(current_info.header, registry)
    
    if current_info.cpp then
        coroutine.yield()
        local cpp_map, _, cpp_list = parse_file_content(current_info.cpp, registry)
        
        local main_class_name = current_info.name
        local main_class_data = h_map[main_class_name]

        if main_class_data then
            if cpp_map[main_class_name] then
                merge_class_data(main_class_data, cpp_map[main_class_name])
            end
            local main_node = build_class_node(main_class_data, registry, render_seen_ids)
            main_node:expand()
            table.insert(root_nodes, main_node)
        else
            for _, class_data in ipairs(h_list) do
                if cpp_map[class_data.text] then
                    merge_class_data(class_data, cpp_map[class_data.text])
                end
                local node = build_class_node(class_data, registry, render_seen_ids)
                node:expand()
                table.insert(root_nodes, node)
            end
        end
    else
         local main_class_name = current_info.name
         local main_class_data = h_map[main_class_name]
         if main_class_data then
            local main_node = build_class_node(main_class_data, registry, render_seen_ids)
            main_node:expand()
            table.insert(root_nodes, main_node)
         else
            for _, class_data in ipairs(h_list) do
                local node = build_class_node(class_data, registry, render_seen_ids)
                node:expand()
                table.insert(root_nodes, node)
            end
         end
    end

    return root_nodes
end

local function build_tree_fallback(file_path, registry, render_seen_ids)
    local map, global, list = parse_file_content(file_path, registry)
    local nodes = {}
    
    for _, cdata in ipairs(list) do
        local node = build_class_node(cdata, registry, render_seen_ids)
        node:expand()
        table.insert(nodes, node)
    end
    
    if #global.methods > 0 or #global.fields > 0 then
        local g_children = {}
        for _, item in ipairs(global.methods) do 
            local safe_id = safe_node_id(item.id, render_seen_ids)
            table.insert(g_children, Tree.Node(vim.tbl_extend("force", item, {id=safe_id}))) 
        end
        for _, item in ipairs(global.fields) do 
            local safe_id = safe_node_id(item.id, render_seen_ids)
            table.insert(g_children, Tree.Node(vim.tbl_extend("force", item, {id=safe_id}))) 
        end
        local raw_gid = registry:get("global_scope")
        local safe_gid = safe_node_id(raw_gid, render_seen_ids)
        local g_node = Tree.Node({ text = "Global", kind = "Info", id = safe_gid }, g_children)
        table.insert(nodes, g_node)
    end
    
    return nodes
end

M.parse_file_content = parse_file_content
M.build_tree_from_context_async = build_tree_from_context_async
M.build_tree_fallback = build_tree_fallback
M.safe_node_id = safe_node_id
M.new_global_data = new_global_data

return M

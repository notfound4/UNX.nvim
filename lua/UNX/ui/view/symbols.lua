-- lua/UNX/ui/view/symbols.lu-- lua/UNX/ui/view/symbols.lua
local Tree = require("nui.tree")
local Line = require("nui.line")

local M = {}
local config = {}

-- ======================================================
-- DEBUG LOGGING
-- ======================================================
local function debug_log(fmt, ...)
    -- local msg = string.format("[UNX-SYM] " .. fmt, ...)
    -- vim.api.nvim_command("echomsg '" .. msg:gsub("'", "''") .. "'")
end

-- ======================================================
-- TREE-SITTER LOGIC
-- ======================================================

local CPP_QUERY = [[
  ; --- Access Specifiers ---
  (access_specifier) @access_label

  ; --- Classes & Structs ---
  (unreal_class_declaration name: (_) @class_name) @definition.uclass
  (unreal_struct_declaration name: (_) @struct_name) @definition.ustruct
  (unreal_enum_declaration name: (_) @enum_name) @definition.uenum
  
  (class_specifier name: (_) @class_name) @definition.class
  (struct_specifier name: (_) @struct_name) @definition.struct

  ; --- Functions (Definitions) ---
  (function_definition
    declarator: [
      (function_declarator declarator: (_) @func_name)
      (pointer_declarator declarator: (function_declarator declarator: (_) @func_name))
      (pointer_declarator (function_declarator declarator: (_) @func_name))
      (reference_declarator (function_declarator declarator: (_) @func_name))
      (field_identifier) @func_name
      (identifier) @func_name
    ]
  ) @definition.function

  ; --- Methods (Declarations inside class) ---
  (field_declaration
    declarator: [
      (function_declarator declarator: (_) @func_name)
      (pointer_declarator declarator: (function_declarator declarator: (_) @func_name))
      (reference_declarator (function_declarator declarator: (_) @func_name))
    ]
  ) @definition.method

  ; 4. コンストラクタ/デストラクタ (型なし宣言)
  (declaration
    (function_declarator
      declarator: (_) @func_name
    )
  ) @definition.method

  ; --- Properties ---
  (field_declaration
    declarator: [
      (field_identifier) @field_name
      (pointer_declarator declarator: (_) @field_name)
      (pointer_declarator (_) @field_name)
      (array_declarator declarator: (_) @field_name)
      (array_declarator (_) @field_name)
      (reference_declarator (_) @field_name)
    ]
  ) @definition.field
]]

local function has_child_type(node, type_name)
    local count = node:child_count()
    for i = 0, count - 1 do
        local child = node:child(i)
        if child:type() == type_name then
            return true
        end
    end
    return false
end

local function get_base_class_name(definition_node, bufnr)
    for child in definition_node:iter_children() do
        if child:type() == "base_class_clause" then
            local base = child:named_child(0)
            if base then
                return vim.treesitter.get_node_text(base, bufnr)
            end
        end
    end
    return nil
end

local function get_node_text(node, bufnr)
    if not node then return "" end
    return vim.treesitter.get_node_text(node, bufnr)
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
        if type == "function_definition" or type == "field_declaration" then return true end
        parent = parent:parent()
    end
    return false
end

local function build_nui_nodes(data_list)
    local nodes = {}
    for _, data in ipairs(data_list) do
        local children = nil
        if data.children and #data.children > 0 then
            children = build_nui_nodes(data.children)
        end
        local node = Tree.Node({
            text = data.text,
            detail = data.detail,
            kind = data.kind,
            line = data.line,
            id = data.id
        }, children)
        if children then node:expand() end
        table.insert(nodes, node)
    end
    return nodes
end

local function parse_buffer_symbols(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then return {} end
    
    local ft = vim.bo[bufnr].filetype
    if ft ~= "cpp" and ft ~= "c" and ft ~= "cp" then 
        return { Tree.Node({ text = "Not a C++ file (" .. ft .. ")", kind = "Info" }) } 
    end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, ft)
    if not ok or not parser then return { Tree.Node({ text = "No Tree-sitter parser", kind = "Info" }) } end

    local tree_root = parser:parse()[1]:root()
    local query_ok, query = pcall(vim.treesitter.query.parse, ft, CPP_QUERY)
    if not query_ok then return { Tree.Node({ text = "Query Error", kind = "Info" }) } end

    local roots_data = {}
    local last_class_data = nil
    local last_class_range = { -1, -1, -1, -1 }
    local symbol_count = 0

    -- ★追加: ID重複防止用の管理テーブル
    local seen_ids = {}
    -- ★追加: ユニークなIDを生成するヘルパー
    local function get_unique_id(base_id)
        if not seen_ids[base_id] then
            seen_ids[base_id] = 1
            return base_id
        else
            local count = seen_ids[base_id]
            seen_ids[base_id] = count + 1
            return string.format("%s_dup%d", base_id, count)
        end
    end

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

        -- === Class / Struct / Enum ===
        if capture_name == "class_name" or capture_name == "struct_name" or capture_name == "enum_name" then
            symbol_count = symbol_count + 1
            local kind = "Class"
            if capture_name == "struct_name" then kind = "Struct" end
            if capture_name == "enum_name" then kind = "Enum" end
            
            local type = definition_node:type()
            if type == "unreal_class_declaration" then kind = "UClass" end
            if type == "unreal_struct_declaration" then kind = "UStruct" end
            if type == "unreal_enum_declaration" then kind = "UEnum" end

            local base_class_text = get_base_class_name(definition_node, bufnr)

            local raw_id = string.format("%s_%d_%d", text, line_num, s_col)
            local unique_id = get_unique_id(raw_id)

            local class_data = {
                text = text, kind = kind, line = line_num,
                id = unique_id,
                children = {}
            }

            last_class_data = class_data
            last_class_range = { definition_node:range() }

            if base_class_text then
                local parent_raw_id = string.format("base_%s_for_%s", base_class_text, unique_id)
                local parent_unique_id = get_unique_id(parent_raw_id)
                
                local parent_data = {
                    text = base_class_text, kind = "BaseClass",
                    id = parent_unique_id,
                    children = { class_data }
                }
                table.insert(roots_data, parent_data)
            else
                table.insert(roots_data, class_data)
            end
            
        -- === Access Specifier ===
        elseif capture_name == "access_label" then
            local raw_id = string.format("access_%d_%d", line_num, s_col)
            local access_data = {
                text = text, kind = "Access", line = line_num,
                id = get_unique_id(raw_id),
            }
            if last_class_data and s_row >= last_class_range[1] and s_row <= last_class_range[3] then
                table.insert(last_class_data.children, access_data)
            else
                table.insert(roots_data, access_data)
            end

        -- === Function / UFUNCTION ===
        elseif capture_name == "func_name" then
            symbol_count = symbol_count + 1
            local kind = "Function"
            if has_child_type(definition_node, "ufunction_macro") then kind = "UFunction" end

            if last_class_data and (text == last_class_data.text or text == "~" .. last_class_data.text) then
                kind = "Constructor"
            end

            local params = get_parameters_text(node, bufnr)

            local inside_class = false
            if last_class_data then
                if s_row >= last_class_range[1] and e_row <= last_class_range[3] then
                    inside_class = true
                end
            end

            local raw_id = string.format("%s_%d_%d", text, line_num, s_col)
            local func_data = {
                text = text, detail = params, kind = kind, line = line_num,
                id = get_unique_id(raw_id)
            }

            if inside_class then
                table.insert(last_class_data.children, func_data)
            else
                -- クラス外の関数 (必要ならルートへ)
                table.insert(roots_data, func_data)
            end

        -- === Field / UPROPERTY ===
        elseif capture_name == "field_name" then
            symbol_count = symbol_count + 1
            local kind = "Field"
            if has_child_type(definition_node, "uproperty_macro") then kind = "UProperty" end

            local inside_class = false
            if last_class_data then
                if s_row >= last_class_range[1] and e_row <= last_class_range[3] then
                    inside_class = true
                end
            end
            
            local raw_id = string.format("%s_%d_%d", text, line_num, s_col)
            local field_data = {
                text = text, kind = kind, line = line_num,
                id = get_unique_id(raw_id)
            }

            if inside_class then
                table.insert(last_class_data.children, field_data)
            end
        end
        
        ::continue::
    end

    if symbol_count == 0 then
        return { Tree.Node({ text = "No symbols found", kind = "Info" }) }
    end

    return build_nui_nodes(roots_data)
end

-- ======================================================
-- RENDERER
-- ======================================================

local function prepare_node(node)
    local line = Line()
    line:append(string.rep("  ", node:get_depth() - 1))
    
    local icon = " "
    local icon_hl = "Normal"
    local text_hl = "UNXFileName"
    
    if node.kind == "BaseClass" then
        icon = "󰜮 "
        icon_hl = "UNXGitRenamed"
        text_hl = "Comment"
    elseif node.kind == "UClass" then
        icon = "UE "
        icon_hl = "UNXGitAdded"
        text_hl = "Type"
    elseif node.kind == "UStruct" then
        icon = "US "
        icon_hl = "UNXGitAdded"
        text_hl = "Type"
    elseif node.kind == "UEnum" then
        icon = "En "
        icon_hl = "UNXGitAdded"
        text_hl = "Type"
    elseif node.kind == "Class" then 
        icon = "󰌗 " 
        icon_hl = "Type"
        text_hl = "Type"
    elseif node.kind == "Struct" then
        icon = "󰌗 "
        icon_hl = "Type"
        text_hl = "Type"
    elseif node.kind == "UFunction" then
        icon = "UF "
        icon_hl = "UNXModifiedIcon"
        text_hl = "Function"
    elseif node.kind == "Function" then
        icon = "󰊕 "
        icon_hl = "Function"
    elseif node.kind == "Constructor" then
        icon = " "
        icon_hl = "Special"
    elseif node.kind == "UProperty" then
        icon = "UP "
        icon_hl = "UNXDirectoryIcon"
    elseif node.kind == "Field" then
        icon = " "
        icon_hl = "Identifier"
    elseif node.kind == "Access" then
        icon = " "
        icon_hl = "Special"
        text_hl = "Special"
    elseif node.kind == "Info" then
        icon = " "
        icon_hl = "Comment"
    end

    line:append(icon, icon_hl)
    line:append(node.text, text_hl)
    
    if node.detail and node.detail ~= "" then
        line:append(node.detail, "Comment")
    end

    return line
end

-- ======================================================
-- PUBLIC API
-- ======================================================

function M.setup(user_config)
    config = user_config
end

function M.create(bufnr)
    return Tree({
        bufnr = bufnr,
        nodes = {},
        prepare_node = prepare_node,
    })
end

function M.update(tree_instance, target_winid)
    if not tree_instance then return end
    
    local current_buf = vim.api.nvim_get_current_buf()
    local ft = vim.bo[current_buf].filetype
    if ft == "unx-explorer" or ft == "neo-tree" or ft == "TelescopePrompt" then return end

    local nodes = parse_buffer_symbols(current_buf)
    tree_instance:set_nodes(nodes)
    tree_instance:render()
    
    if target_winid and vim.api.nvim_win_is_valid(target_winid) then
        local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(current_buf), ":t")
        if fname == "" then fname = "No Name" end
        local icon = "󰌗"
        if ft == "cpp" then icon = "" elseif ft == "h" then icon = "" end
        pcall(vim.api.nvim_win_set_option, target_winid, "winbar", string.format("%%#UNXGitFunction# %s %s", icon, fname))
    end
end

function M.on_node_action(tree_instance, split_instance, other_split_instance)
    local node = tree_instance:get_node()
    if not node or not node.line then return end
    
    local wins = vim.api.nvim_list_wins()
    for _, w in ipairs(wins) do
        if w ~= split_instance.winid and (not other_split_instance or w ~= other_split_instance.winid) then
            vim.api.nvim_set_current_win(w)
            vim.api.nvim_win_set_cursor(w, { node.line, 0 })
            vim.cmd("normal! zz")
            break
        end
    end
end

return M

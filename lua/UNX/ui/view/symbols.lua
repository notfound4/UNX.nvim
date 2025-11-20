-- lua/UNX/ui/view/symbols.lua
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

-- ★修正: child_by_field_name を使わずに安全に型参照判定を行う
local function is_type_reference(node)
    local parent = node:parent()
    while parent do
        local type = parent:type()
        
        -- 引数宣言の中にある場合は参照とみなす
        if type == "parameter_declaration" then return true end
        
        -- フィールド宣言 (メンバ変数定義) の場合
        if type == "field_declaration" then
            -- 'type' フィールドかどうかを判定したいが、メソッドがない場合があるため
            -- 「最初の名前付き子要素 (named_child(0)) が自分自身であれば、それは型定義である」とみなす
            -- (C++のfield_declarationは通常、最初の子が型、次が宣言子)
            local first_child = parent:named_child(0)
            if first_child and node:id() == first_child:id() then
                return true
            end
        end
        
        if type:match("definition") or type:match("declaration") then break end
        parent = parent:parent()
    end
    return false
end

-- 中間データ構造から Nui Node を再帰的に作成する関数
local function build_nui_nodes(data_list)
    local nodes = {}
    for _, data in ipairs(data_list) do
        local children = nil
        if data.children and #data.children > 0 then
            children = build_nui_nodes(data.children)
        end
        
        local node = Tree.Node({
            text = data.text,
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

    for id, node, metadata in query:iter_captures(tree_root, bufnr, 0, -1) do
        local capture_name = query.captures[id]
        
        -- 型参照（定義ではないもの）はスキップ
        if is_type_reference(node) then
            goto continue
        end

        local text = vim.treesitter.get_node_text(node, bufnr)
        local s_row, s_col, e_row, _ = node:range()
        local line_num = s_row + 1
        
        local definition_node = node
        while definition_node do
            local type = definition_node:type()
            if type:match("declaration") or type:match("specifier") or type:match("definition") then
                break
            end
            definition_node = definition_node:parent()
        end
        if not definition_node then definition_node = node end

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

            local class_data = {
                text = text, kind = kind, line = line_num,
                id = string.format("%s_%d_%d", text, line_num, s_col),
                children = {}
            }

            last_class_data = class_data
            last_class_range = { definition_node:range() }

            if base_class_text then
                local parent_data = {
                    text = base_class_text, kind = "BaseClass",
                    id = string.format("base_%s_for_%s", base_class_text, class_data.id),
                    children = { class_data }
                }
                table.insert(roots_data, parent_data)
            else
                table.insert(roots_data, class_data)
            end

        elseif capture_name == "func_name" then
            symbol_count = symbol_count + 1
            local kind = "Function"
            if has_child_type(definition_node, "ufunction_macro") then kind = "UFunction" end

            local inside_class = false
            if last_class_data then
                if s_row >= last_class_range[1] and e_row <= last_class_range[3] then
                    inside_class = true
                end
            end

            local func_data = {
                text = text, kind = kind, line = line_num,
                id = string.format("%s_%d_%d", text, line_num, s_col)
            }

            if inside_class then
                table.insert(last_class_data.children, func_data)
            end

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
            
            local field_data = {
                text = text, kind = kind, line = line_num,
                id = string.format("%s_%d_%d", text, line_num, s_col)
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
    elseif node.kind == "UProperty" then
        icon = "UP "
        icon_hl = "UNXDirectoryIcon"
    elseif node.kind == "Field" then
        icon = " "
        icon_hl = "Identifier"
    elseif node.kind == "Info" then
        icon = " "
        icon_hl = "Comment"
    end

    line:append(icon, icon_hl)
    line:append(node.text, text_hl)
    
    if node.line then
        line:append(string.format(" :%d", node.line), "Comment")
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

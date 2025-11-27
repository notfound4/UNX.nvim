-- lua/UNX/parser/symbols.lua
local IDRegistry = require("UNX.common.id_registry")
local logger = require("UNX.logger")
local Tree = require("nui.tree")
local unl_path = require("UNL.path")

-- ★変更: UNLのパーサーを利用
local UnlCppParser = require("UNL.parser.cpp")

local M = {}

-- ======================================================
-- 1. UNLデータ -> UNX用ノード変換ロジック
-- ======================================================

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

-- クラスデータのマージ (Header + Cpp の結果結合)
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

-- UNLのClassDataからNui Treeノードを構築
local function build_class_node(class_data, registry, render_seen_ids)
    local children = {}
    
    -- ID生成ヘルパー (ファイルハッシュ + シンボル名 + 行数)
    local file_hash = IDRegistry.get_file_hash(class_data.file_path)
    local class_base_id = string.format("%s_%s_%d", file_hash, class_data.name, class_data.line)
    
    local function make_group_id(suffix)
        local raw_id = registry:get(class_base_id .. suffix)
        return safe_node_id(raw_id, render_seen_ids)
    end
    
    local function make_item_node(item)
        local raw_id = string.format("%s_%s_%d", file_hash, item.name, item.line)
        local unique_id = safe_node_id(registry:get(raw_id), render_seen_ids)
        
        -- UNLデータ(name)をUNXのTree用(text)にマッピング
        local node_opts = {
            text = item.name,
            detail = item.detail,
            kind = item.kind,
            line = item.line,
            file_path = item.file_path,
            id = unique_id
        }
        return Tree.Node(node_opts)
    end

    -- フィールド（変数）
    local field_group_children = {}
    for _, access in ipairs({"public", "protected", "private", "impl"}) do
        local items = class_data.fields[access]
        if items and #items > 0 then
            if access == "impl" then
                for _, item in ipairs(items) do table.insert(field_group_children, make_item_node(item)) end
            else
                local access_node_children = {}
                for _, item in ipairs(items) do table.insert(access_node_children, make_item_node(item)) end
                local access_node = Tree.Node({ text = access .. ":", kind = "Access", id = make_group_id("_f_" .. access) }, access_node_children)
                access_node:expand()
                table.insert(field_group_children, access_node)
            end
        end
    end
    if #field_group_children > 0 then
        table.insert(children, Tree.Node({ text = "Members", kind = "GroupFields", id = make_group_id("_group_fields") }, field_group_children))
    end

    -- メソッド（関数）
    local func_group_children = {}
    for _, access in ipairs({"public", "protected", "private"}) do
        local items = class_data.methods[access]
        if items and #items > 0 then
            local access_node_children = {}
            for _, item in ipairs(items) do table.insert(access_node_children, make_item_node(item)) end
            local access_node = Tree.Node({ text = access .. ":", kind = "Access", id = make_group_id("_m_" .. access) }, access_node_children)
            access_node:expand()
            table.insert(func_group_children, access_node)
        end
    end
    -- 実装 (.cpp)
    local impl_items = class_data.methods["impl"]
    if impl_items and #impl_items > 0 then
        local impl_children = {}
        for _, item in ipairs(impl_items) do table.insert(impl_children, make_item_node(item)) end
        table.insert(func_group_children, Tree.Node({ text = "Implementations (.cpp)", kind = "Access", id = make_group_id("_impls_group") }, impl_children))
    end
    if #func_group_children > 0 then
        local group_node = Tree.Node({ text = "Functions", kind = "GroupMethods", id = make_group_id("_group_funcs") }, func_group_children)
        group_node:expand()
        table.insert(children, group_node)
    end

    local class_node_id = safe_node_id(registry:get(class_base_id), render_seen_ids)
    local node = Tree.Node({
        text = class_data.name, kind = class_data.kind, line = class_data.line, id = class_node_id,
        file_path = class_data.file_path
    }, children)
    
    node:expand()
    return node, children
end


-- ======================================================
-- 2. メインビルドロジック (UNL呼び出し)
-- ======================================================

local function build_tree_from_context_async(context, registry, render_seen_ids)
    local root_nodes = {}
    
    -- 親クラス (Lazy Load)
    if context.parents then
        for i = #context.parents, 1, -1 do
            coroutine.yield()
            local parent_info = context.parents[i]
            if parent_info.header then
                local safe_id = safe_node_id(registry:get("base_" .. parent_info.name), render_seen_ids)
                local p_node = Tree.Node({
                    text = parent_info.name, kind = "BaseClass", id = safe_id,
                    file_path = parent_info.header, lazy_load = true, _has_children = true 
                })
                p_node:collapse()
                table.insert(root_nodes, p_node)
            end
        end
    end

    local current_info = context.current
    if not current_info or not current_info.header then return root_nodes end

    coroutine.yield()
    -- ★変更: UNLパーサー呼び出し (Header)
    local h_result = UnlCppParser.parse(current_info.header)
    
    if current_info.cpp then
        coroutine.yield()
        -- ★変更: UNLパーサー呼び出し (Cpp)
        local cpp_result = UnlCppParser.parse(current_info.cpp)
        
        -- ★変更: UNLのヒューリスティック関数を利用
        local main_class_data = UnlCppParser.find_best_match_class(h_result, current_info.name)

        if main_class_data then
            -- 実装側のデータをマージ
            local cpp_class_data = cpp_result.map[current_info.name] -- 完全一致で検索
            if cpp_class_data then
                merge_class_data(main_class_data, cpp_class_data)
            end
            local main_node = build_class_node(main_class_data, registry, render_seen_ids)
            table.insert(root_nodes, main_node)
        else
            -- 見つからない場合はリスト全てを表示
            for _, class_data in ipairs(h_result.list) do
                local cpp_data = cpp_result.map[class_data.name]
                if cpp_data then merge_class_data(class_data, cpp_data) end
                local node = build_class_node(class_data, registry, render_seen_ids)
                table.insert(root_nodes, node)
            end
        end
    else
         -- ヘッダーのみの場合
         local main_class_data = UnlCppParser.find_best_match_class(h_result, current_info.name)
         if main_class_data then
            local main_node = build_class_node(main_class_data, registry, render_seen_ids)
            table.insert(root_nodes, main_node)
         else
            for _, class_data in ipairs(h_result.list) do
                local node = build_class_node(class_data, registry, render_seen_ids)
                table.insert(root_nodes, node)
            end
         end
    end

    return root_nodes
end

local function build_tree_fallback(file_path, registry, render_seen_ids)
    -- ★変更: UNLパーサー呼び出し
    local result = UnlCppParser.parse(file_path)
    local nodes = {}
    
    for _, cdata in ipairs(result.list) do
        local node = build_class_node(cdata, registry, render_seen_ids)
        table.insert(nodes, node)
    end
    
    -- グローバル要素の表示
    if #result.globals.methods > 0 or #result.globals.fields > 0 then
        -- 簡易的なグローバル表示ロジック（必要に応じてbuild_class_node相当の処理を追加）
        -- 今回は省略
    end
    
    return nodes
end

-- 遅延読み込み用
local function parse_and_get_children(file_path, target_class_name)
    local registry = IDRegistry.new()
    local render_seen_ids = {}
    
    -- ★変更: UNLパーサー呼び出し
    local result = UnlCppParser.parse(file_path)
    
    -- ★変更: UNLのヒューリスティック関数を利用
    local class_data = UnlCppParser.find_best_match_class(result, target_class_name)
    
    if class_data then
        local _, children = build_class_node(class_data, registry, render_seen_ids)
        return children or {}
    end
    
    return {}
end

M.build_tree_from_context_async = build_tree_from_context_async
M.build_tree_fallback = build_tree_fallback
M.parse_and_get_children = parse_and_get_children

return M

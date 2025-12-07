local IDRegistry = require("UNX.common.id_registry")
local Tree = require("nui.tree")
local unl_api = require("UNL.api")

local M = {}

local function safe_node_id(id, seen_ids)
    if not id then return "unknown_" .. vim.loop.hrtime() end
    if not seen_ids[id] then
        seen_ids[id] = true
        return id
    else
        local count = 1
        local new_id = id .. "_dup" .. count
        while seen_ids[new_id] do
            count = count + 1
            new_id = id .. "_dup" .. count
        end
        seen_ids[new_id] = true
        return new_id
    end
end

local function build_class_node(class_data, registry, render_seen_ids)
    local children = {}
    local file_hash = IDRegistry.get_file_hash(class_data.file_path)
    local class_base_id = string.format("%s_%s_%d", file_hash, class_data.name, class_data.line)

    local function make_group_id(suffix)
        local raw = registry:get(class_base_id .. suffix)
        return safe_node_id(raw, render_seen_ids)
    end

    local function make_item_node(item)
        local raw = string.format("%s_%s_%d", file_hash, item.name, item.line)
        local unique = safe_node_id(registry:get(raw), render_seen_ids)
        return Tree.Node({
            text = item.name,
            detail = item.detail,
            kind = item.kind,
            line = item.line,
            file_path = item.file_path,
            id = unique
        })
    end

    -- Fields
    local field_children = {}
    for _, access in ipairs({"public", "protected", "private", "impl"}) do
        if class_data.fields and class_data.fields[access] then
            for _, f in ipairs(class_data.fields[access]) do
                table.insert(field_children, make_item_node(f))
            end
        end
    end
    if #field_children > 0 then
        table.insert(children, Tree.Node({ text = "Properties", kind = "GroupFields", id = make_group_id("_props") }, field_children))
    end

    -- Methods
    local func_children = {}
    for _, access in ipairs({"public", "protected", "private"}) do
        if class_data.methods and class_data.methods[access] then
            for _, m in ipairs(class_data.methods[access]) do
                table.insert(func_children, make_item_node(m))
            end
        end
    end
    -- Implementations (.cpp)
    if class_data.methods and class_data.methods["impl"] then
        local impl_children = {}
        for _, m in ipairs(class_data.methods["impl"]) do
            table.insert(impl_children, make_item_node(m))
        end
        if #impl_children > 0 then
            table.insert(func_children, Tree.Node({ text = "Implementations", kind = "GroupMethods", id = make_group_id("_impls") }, impl_children))
        end
    end

    if #func_children > 0 then
        table.insert(children, Tree.Node({ text = "Functions", kind = "GroupMethods", id = make_group_id("_funcs") }, func_children))
    end

    local node = Tree.Node({
        text = class_data.name,
        kind = class_data.kind,
        line = class_data.line,
        file_path = class_data.file_path,
        id = safe_node_id(registry:get(class_base_id), render_seen_ids),
        _has_children = (#children > 0),
    }, children)
    
    node:expand()
    return node
end

-- ======================================================
-- 公開API
-- ======================================================

function M.fetch_and_build(file_path, on_complete)
    -- UCMプロバイダーへリクエスト
    -- UNLの仕様: requestは (success, result) を返す
    local ok, symbols = unl_api.provider.request("ucm.get_file_symbols", {
        file_path = file_path
    })

    local registry = IDRegistry.new()
    local seen_ids = {}
    local nodes = {}

    -- 成功かつ結果がテーブルである場合のみ処理
    if ok and symbols and type(symbols) == "table" then
        for _, item in ipairs(symbols) do
            if item.kind == "UClass" or item.kind == "Class" or item.kind == "UStruct" or item.kind == "Struct" then
                table.insert(nodes, build_class_node(item, registry, seen_ids))
            else
                local id = safe_node_id(registry:get(item.name .. item.line), seen_ids)
                table.insert(nodes, Tree.Node({
                    text = item.name,
                    kind = item.kind,
                    line = item.line,
                    file_path = item.file_path,
                    id = id
                }))
            end
        end
    end

    if on_complete then on_complete(nodes) end
end

-- 遅延ロード用 (今回は使いませんがAPI互換のため残します)
function M.parse_and_get_children(file_path, class_name)
    local ok, symbols = unl_api.provider.request("ucm.get_file_symbols", { file_path = file_path })
    if ok and symbols and type(symbols) == "table" then
        local registry = IDRegistry.new()
        local seen = {}
        for _, item in ipairs(symbols) do
            if item.name == class_name then
                local node = build_class_node(item, registry, seen)
                return node:get_child_ids() and node:get_children() or {}
            end
        end
    end
    return {}
end

return M

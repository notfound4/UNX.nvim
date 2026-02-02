local Tree = require("nui.tree")
local Line = require("nui.line")
local unl_api = require("UNL.api")
local unl_open = require("UNL.buf.open")
local unl_path = require("UNL.path")
local unl_parser_ini = require("UNL.parser.ini")
local ctx_uproject = require("UNX.context.uproject")
local fs = require("vim.fs")

local M = {}

local active_tree = nil

-- =====================================================================
-- 1. Helper Functions
-- =====================================================================

local function apply_config_op(current, op, new_value)
    local is_array = type(current) == "table"
    if op == "!" then return nil
    elseif op == "-" then
        if is_array then
            local filtered = {}
            for _, v in ipairs(current) do if v ~= new_value then table.insert(filtered, v) end end
            return #filtered > 0 and filtered or nil
        elseif current == new_value then return nil end
        return current
    elseif op == "+" then
        if not current then return { new_value } end
        if not is_array then current = { current } end
        table.insert(current, new_value)
        return current
    else return new_value end
end

local function format_value_for_display(val)
    if type(val) == "table" then return string.format("[Array x%d] %s", #val, val[#val]) end
    if not val then return "nil" end
    if #val > 50 then return val:sub(1, 47) .. "..." end
    return val
end

local function parse_device_profiles_ini(filepath, profiles_map)
    local parsed = unl_parser_ini.parse(filepath)
    if not parsed or not parsed.sections then return end
    local filename_short = vim.fn.fnamemodify(filepath, ":t")

    for section_name, items in pairs(parsed.sections) do
        local profile_name = section_name:match("^(.*)%s+DeviceProfile$")
        if profile_name then
            if not profiles_map[profile_name] then
                local parent_plat = profile_name:match("^([^_]+)") or profile_name
                profiles_map[profile_name] = {
                    name = profile_name,
                    parent_platform = parent_plat,
                    cvars = {}
                }
            end
            for _, item in ipairs(items) do
                if item.key == "CVars" or item.key == "+CVars" then
                    local cvar_key, cvar_val = item.value:match("^([^=]+)=(.*)$")
                    if cvar_key then
                        table.insert(profiles_map[profile_name].cvars, {
                            key = vim.trim(cvar_key),
                            value = vim.trim(cvar_val or ""),
                            op = "", 
                            line = item.line,
                            raw_file = filename_short,
                            full_path = filepath
                        })
                    end
                end
            end
        end
    end
end

local function get_available_device_profiles(project_root, engine_root)
    local profiles = {} 
    if engine_root then
        parse_device_profiles_ini(fs.joinpath(engine_root, "Engine/Config/BaseDeviceProfiles.ini"), profiles)
    end
    if project_root then
        parse_device_profiles_ini(fs.joinpath(project_root, "Config/DefaultDeviceProfiles.ini"), profiles)
    end
    return profiles
end

local function get_available_platforms(engine_root)
    local config_root = fs.joinpath(engine_root, "Engine", "Config")
    local platforms = {}
    local seen = {}
    
    local handle = vim.loop.fs_scandir(config_root)
    if handle then
        while true do
            local name, type = vim.loop.fs_scandir_next(handle)
            if not name then break end
            if (type == "directory" or type == "link") and not name:match("^%.") then
                local check_ini = fs.joinpath(config_root, name, name .. "Engine.ini")
                local check_ddpi = fs.joinpath(config_root, name, "DataDrivenPlatformInfo.ini")
                if vim.fn.filereadable(check_ini) == 1 or vim.fn.filereadable(check_ddpi) == 1 then
                    table.insert(platforms, name); seen[name] = true
                end
            end
        end
    end
    
    local major = { "Windows", "Mac", "Linux", "Android", "IOS", "TVOS", "Apple", "Unix" }
    for _, p in ipairs(major) do
        if not seen[p] then
            local p_dir = fs.joinpath(config_root, p)
            if vim.fn.isdirectory(p_dir) == 1 then table.insert(platforms, p); seen[p] = true end
        end
    end
    table.sort(platforms)
    return platforms
end

local function get_config_stack(project_root, engine_root, target)
    local stack = {}
    local platform = target.platform 
    
    if engine_root then 
        table.insert(stack, { type="file", path=fs.joinpath(engine_root, "Engine/Config/Base.ini") })
        table.insert(stack, { type="file", path=fs.joinpath(engine_root, "Engine/Config/BaseEngine.ini") })
    end
    
    if engine_root and platform then
        if platform == "Mac" or platform == "IOS" or platform == "TVOS" then
            table.insert(stack, { type="file", path=fs.joinpath(engine_root, "Engine/Config/Apple/AppleEngine.ini") })
        end
        if platform == "Linux" then
            table.insert(stack, { type="file", path=fs.joinpath(engine_root, "Engine/Config/Unix/UnixEngine.ini") })
        end
    end

    if engine_root and platform and platform ~= "Default" then
        table.insert(stack, { type="file", path=fs.joinpath(engine_root, "Engine/Config", platform, platform .. "Engine.ini") })
    end

    if project_root then 
        table.insert(stack, { type="file", path=fs.joinpath(project_root, "Config/DefaultEngine.ini") })
    end
    
    if project_root and platform and platform ~= "Default" then
        table.insert(stack, { type="file", path=fs.joinpath(project_root, "Config", platform, platform .. "Engine.ini") })
    end
    
    if target.is_profile and target.cvars then
        local virtual_section = "SystemSettings" 
        local virtual_data = { [virtual_section] = {} }
        for _, cvar in ipairs(target.cvars) do
            table.insert(virtual_data[virtual_section], {
                key = cvar.key, value = cvar.value, op = cvar.op, line = cvar.line,
                raw_file = "Profile: " .. cvar.raw_file, full_path = cvar.full_path
            })
        end
        table.insert(stack, { type="virtual", data=virtual_data, name=target.name })
    end
    return stack
end

local function resolve_config_settings(stack)
    local resolved = {} 
    for _, source in ipairs(stack) do
        local sections_data = nil
        local source_name = ""
        local full_path = ""
        if source.type == "file" then
            local parsed = unl_parser_ini.parse(source.path)
            if parsed then sections_data = parsed.sections end
            full_path = source.path
            source_name = vim.fn.fnamemodify(source.path, ":t")
            local parent = vim.fn.fnamemodify(source.path, ":h:t")
            if parent ~= "Config" then source_name = parent .. "/" .. source_name end
        elseif source.type == "virtual" then
            sections_data = source.data
            source_name = source.name 
            full_path = "DeviceProfile"
        end
        if sections_data then
            for section, items in pairs(sections_data) do
                if not resolved[section] then resolved[section] = {} end
                for _, item in ipairs(items) do
                    local key = item.key
                    if not resolved[section][key] then
                        resolved[section][key] = { value = nil, history = {} }
                    end
                    local entry = resolved[section][key]
                    entry.value = apply_config_op(entry.value, item.op, item.value)
                    table.insert(entry.history, {
                        file = source.type == "virtual" and item.raw_file or source_name,
                        full_path = source.type == "virtual" and item.full_path or full_path,
                        value = format_value_for_display(entry.value),
                        op = item.op, line = item.line
                    })
                end
            end
        end
    end
    return resolved
end

local function build_config_tree_nodes(project_root, engine_root)
    local targets_map = {}
    local targets_order = {}
    local function add_or_merge_target(t)
        if not targets_map[t.name] then
            targets_map[t.name] = t
            table.insert(targets_order, t.name)
        else
            local existing = targets_map[t.name]
            if t.cvars and #t.cvars > 0 then existing.cvars = t.cvars; existing.is_profile = true end
            if not existing.platform and t.platform then existing.platform = t.platform end
        end
    end

    add_or_merge_target({ name = "Default (Editor)", platform = "Default" })
    if engine_root then
        local platforms = get_available_platforms(engine_root)
        for _, p in ipairs(platforms) do add_or_merge_target({ name = p, platform = p, is_profile = false }) end
        local profiles = get_available_device_profiles(project_root, engine_root)
        local profile_names = vim.tbl_keys(profiles)
        table.sort(profile_names)
        for _, pname in ipairs(profile_names) do
            local pdata = profiles[pname]
            local parent_valid = (pdata.parent_platform == "Windows")
            if not parent_valid then
                for _, pp in ipairs(platforms) do if pp == pdata.parent_platform then parent_valid = true; break end end
            end
            if parent_valid then add_or_merge_target({ name = pname, platform = pdata.parent_platform, is_profile = true, cvars = pdata.cvars }) end
        end
    end
    
    local root_children = {}
    for _, tname in ipairs(targets_order) do
        local target = targets_map[tname]
        local stack = get_config_stack(project_root, engine_root, target)
        local resolved_data = resolve_config_settings(stack)
        local platform_children = {}
        local sections = vim.tbl_keys(resolved_data); table.sort(sections)
        for _, section in ipairs(sections) do
            local keys_data = resolved_data[section]
            local section_children = {}
            local keys = vim.tbl_keys(keys_data); table.sort(keys)
            for _, key in ipairs(keys) do
                local info = keys_data[key]
                local history_nodes = {}
                for i, h in ipairs(info.history) do
                    table.insert(history_nodes, Tree.Node({
                        text = string.format("%s %s [%s]", h.op == "" and "=" or h.op, h.value, h.file),
                        id = string.format("hist_%s_%s_%s_%d_%d", target.name, section, key, h.line, i),
                        type = "history",
                        extra = { filepath = h.full_path, line = h.line, op = h.op }
                    }))
                end
                table.insert(section_children, Tree.Node({
                    text = key, id = string.format("%s_%s_%s", target.name, section, key),
                    type = "parameter", extra = { final_value = format_value_for_display(info.value) }
                }, history_nodes))
            end
            table.insert(platform_children, Tree.Node({
                text = section, id = string.format("%s_%s", target.name, section), type = "section"
            }, section_children))
        end
        table.insert(root_children, Tree.Node({
            text = target.name, id = "target_" .. target.name, type = target.is_profile and "profile" or "platform"
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
    
    local ctx = ctx_uproject.get()
    if not ctx.project_root then
        tree_instance:set_nodes({ Tree.Node({ text = "No project root.", kind = "Info" }) })
        tree_instance:render(); return
    end

    local nodes = build_config_tree_nodes(ctx.project_root, ctx.engine_root)
    local root_node = Tree.Node({
        text = "Config Explorer", id = "config_logical_root", type = "root"
    }, nodes)
    root_node:expand()
    
    tree_instance:set_nodes({ root_node })
    tree_instance:render()
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

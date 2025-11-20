-- lua/UNX/ui/view/uproject.lua
local Tree = require("nui.tree")
local Line = require("nui.line")
local unl_api = require("UNL.api")
local unl_finder = require("UNL.finder")

-- DevIcons
local has_devicons, devicons = pcall(require, "nvim-web-devicons")

local M = {}
local config = {}

-- リクエスト用コンテキスト保持
local last_context = {
    project_root = nil,
    engine_root = nil,
}

-- ======================================================
-- HELPER FUNCTIONS
-- ======================================================

local function get_opened_buffers_status()
    local opened_buffers = {}
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.fn.buflisted(buffer) ~= 0 then
            local name = vim.api.nvim_buf_get_name(buffer)
            if name == "" then name = "[No Name]#" .. buffer end
            opened_buffers[name] = { modified = vim.bo[buffer].modified }
        end
    end
    return opened_buffers
end

local function get_git_status_lookup()
    return {} 
end

local function get_git_icon_and_hl(status_code)
    local icons = config.uproject and config.uproject.git_icons or {}
    if status_code == "M" then return icons.Modified or "M", "UNXGitModified" end
    if status_code == "A" then return icons.Added or "A", "UNXGitAdded" end
    if status_code == "D" then return icons.Deleted or "D", "UNXGitDeleted" end
    if status_code == "R" then return icons.Renamed or "R", "UNXGitRenamed" end
    if status_code == "C" then return icons.Conflict or "C", "UNXGitConflict" end
    if status_code == "??" then return icons.Untracked or "?", "UNXGitUntracked" end
    if status_code == "!!" then return icons.Ignored or "!", "UNXGitIgnored" end
    return "", "UNXFileName"
end

-- ======================================================
-- DATA FETCHING
-- ======================================================

local function convert_uep_to_nui(uep_node)
    local children = nil
    if uep_node.children and #uep_node.children > 0 then
        children = {}
        for _, child in ipairs(uep_node.children) do
            table.insert(children, convert_uep_to_nui(child))
        end
    end

    local nui_node = Tree.Node({
        text = uep_node.name,
        id = uep_node.id,
        path = uep_node.path,
        type = uep_node.type,
        -- has_children判定: 実際に子供がいるか、またはフラグが立っているか
        _has_children = uep_node.has_children or (children and #children > 0),
        extra = uep_node.extra, 
    }, children)
    
    -- 論理ルートは最初から展開
    if uep_node.id == "logical_root" then
        nui_node:expand()
    end

    return nui_node
end

local function fetch_root_data()
    local cwd = vim.loop.cwd()
    
    local project_info = unl_finder.project.find_project(cwd)
    if not project_info then
        vim.notify("UNX: Not an Unreal Engine project directory.", vim.log.levels.WARN)
        return {}
    end
    
    local engine_root = unl_finder.engine.find_engine_root(project_info.uproject, {
        engine_override_path = config.engine_path 
    })

    last_context.project_root = project_info.root
    last_context.engine_root = engine_root

    local success, result = unl_api.provider.request("uep.build_tree_model", {
        capability = "uep.build_tree_model",
        project_root = project_info.root,
        engine_root = engine_root,
        scope = "Full", -- FullにすることでEngineも正しく含める
        logger_name = "UNX",
    })

    if not success or not result then return {} end
    if result[1] and result[1].type == "message" then return {} end

    local nui_nodes = {}
    for _, item in ipairs(result) do
        table.insert(nui_nodes, convert_uep_to_nui(item))
    end
    return nui_nodes
end

local function lazy_load_children(tree_instance, parent_node)
    if parent_node:has_children() then return end
    
    local success, children = unl_api.provider.request("uep.load_tree_children", {
        capability = "uep.load_tree_children",
        project_root = last_context.project_root,
        engine_root = last_context.engine_root,
        node = { 
            id = parent_node.id, 
            path = parent_node.path,
            name = parent_node.text,
            type = parent_node.type,
            extra = parent_node.extra 
        },
        logger_name = "UNX",
    })

    if success and children then
        local nui_children = {}
        for _, item in ipairs(children) do
            table.insert(nui_children, convert_uep_to_nui(item))
        end
        tree_instance:set_nodes(nui_children, parent_node:get_id())
    end
end

-- ======================================================
-- RENDERER
-- ======================================================

local function prepare_node(node)
    local line = Line()
    line:append(string.rep("  ", node:get_depth() - 1))

    local has_children = node:has_children() or node._has_children

    if has_children then
        local exp_open = config.uproject.icon.expander_open or ""
        local exp_closed = config.uproject.icon.expander_closed or ""
        local icon = node:is_expanded() and exp_open or exp_closed
        line:append(icon .. " ", "UNXIndentMarker") 
    else
        line:append("  ", "UNXIndentMarker")
    end

    local icon_text = config.uproject.icon.default_file or " "
    local icon_hl = "UNXFileIcon"

    if node.type == "directory" then
        local f_open = config.uproject.icon.folder_open or ""
        local f_close = config.uproject.icon.folder_closed or ""
        icon_text = node:is_expanded() and f_open or f_close
        icon_hl = "UNXDirectoryIcon"
    elseif node.type == "file" and has_devicons then
        local filename = node.text
        local ext = node.path and node.path:match("^.+%.(.+)$") or ""
        local dev_icon, dev_hl = devicons.get_icon(filename, ext, { default = true })
        if dev_icon then
            icon_text = dev_icon
            icon_hl = dev_hl
        end
    end

    line:append(icon_text .. " ", icon_hl)

    local path = node.path or node.id
    local opened = get_opened_buffers_status()
    local git = get_git_status_lookup()
    
    local is_modified = opened[path] and opened[path].modified
    local git_stat = git[path]

    local name_hl = "UNXFileName"
    if git_stat then _, name_hl = get_git_icon_and_hl(git_stat) end
    
    line:append(node.text, name_hl)

    if git_stat then
        local g_icon, g_hl = get_git_icon_and_hl(git_stat)
        line:append(" " .. g_icon, g_hl)
    elseif is_modified then
        local m_icon = config.uproject.icon.modified or "[+]"
        line:append(m_icon, "UNXModifiedIcon")
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
        nodes = fetch_root_data(),
        prepare_node = prepare_node,
    })
end

function M.refresh(tree_instance)
    if tree_instance then
        local new_nodes = fetch_root_data()
        tree_instance:set_nodes(new_nodes)
        tree_instance:render()
    end
end

function M.on_node_action(tree_instance, split_instance, other_split_instance)
    local node = tree_instance:get_node()
    if not node then return end
    
    if node:has_children() or node._has_children or node.type == "directory" then
        if node:is_expanded() then
            node:collapse()
        else
            if not node:has_children() then
                lazy_load_children(tree_instance, node)
            end
            node:expand()
        end
        tree_instance:render()
    else
        if node.path then
            local current_win = vim.api.nvim_get_current_win()
            local wins = vim.api.nvim_list_wins()
            local target_win = current_win
            for _, w in ipairs(wins) do
                if w ~= split_instance.winid and (not other_split_instance or w ~= other_split_instance.winid) then
                    target_win = w
                    break
                end
            end
            vim.api.nvim_set_current_win(target_win)
            vim.cmd("edit " .. vim.fn.fnameescape(node.path))
        end
    end
end

return M

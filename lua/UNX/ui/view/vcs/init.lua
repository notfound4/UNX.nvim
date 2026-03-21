-- lua/UNX/ui/view/vcs/init.lua
-- VCS Tab: My Commits (top panel)
local Tree = require("nui.tree")
local Line = require("nui.line")
local vcs = require("UNX.vcs")
local config = require("UNX.config")
local unl_path = require("UNL.path")

local M = {}

function M.setup() end

local VCS_ICONS = {
    git = "",
    p4  = "󰊢",
    svn = "󰜘",
}

function M.create(bufnr)
    local tree = Tree({
        bufnr = bufnr,
        nodes = {},
        prepare_node = function(node)
            local line = Line()
            if node.type == "commit" then
                local icon = VCS_ICONS[node.data.vcs] or ""
                line:append(" " .. icon .. " ", "Comment")
                line:append(node.data.hash, "Special")
                line:append(" " .. node.data.message, "UNXFileName")
                if node.data.date and node.data.date ~= "" then
                    line:append(" (" .. node.data.date .. ")", "Comment")
                end
            elseif node.type == "file" then
                line:append("   ", "UNXFileIcon")
                line:append(node.text, "UNXFileName")
            elseif node.type == "empty" then
                line:append("  " .. node.text, "Comment")
            else
                line:append(node.text)
            end
            return line
        end,
    })

    M.refresh(tree)
    return tree
end

function M.render(tree)
    if tree and tree.bufnr and vim.api.nvim_buf_is_valid(tree.bufnr) then
        tree:render()
    end
end

function M.refresh(tree)
    if not tree or not tree.bufnr or not vim.api.nvim_buf_is_valid(tree.bufnr) then return end

    local conf = config.get().vcs or {}
    local limit = conf.my_commits_limit or 10
    local ctx = require("UNX.context.uproject").get()
    local cwd = ctx.project_root or vim.fn.getcwd()

    vcs.get_my_log(cwd, limit, function(commits)
        if not commits or #commits == 0 then
            tree:set_nodes({ Tree.Node({ text = "No commits found", id = "empty", type = "empty" }) })
            tree:render()
            return
        end

        local nodes = {}
        for _, c in ipairs(commits) do
            table.insert(nodes, Tree.Node({
                text = c.hash .. " " .. c.message,
                id = "my_" .. (c.vcs or "") .. "_" .. c.hash,
                type = "commit",
                data = c,
            }))
        end

        tree:set_nodes(nodes)
        tree:render()
    end)
end

function M.on_node_action(tree)
    if not tree then return end
    local node = tree:get_node()
    if not node then return end

    if node.type == "file" then
        local commit_data = node.data and node.data.commit or {}
        local file_path
        if commit_data._root then
            file_path = unl_path.join(commit_data._root, node.text)
        else
            local ctx = require("UNX.context.uproject").get()
            file_path = unl_path.join(ctx.project_root or vim.fn.getcwd(), node.text)
        end

        if vim.fn.filereadable(file_path) == 1 then
            local target_win = nil
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                local buf = vim.api.nvim_win_get_buf(win)
                local ft = vim.bo[buf].filetype
                local bt = vim.bo[buf].buftype
                if ft ~= "unx-explorer" and bt ~= "nofile" then
                    target_win = win
                    break
                end
            end
            if target_win then
                vim.api.nvim_set_current_win(target_win)
            end
            vim.cmd("edit " .. vim.fn.fnameescape(file_path))
        else
            vim.notify("File not found: " .. file_path, vim.log.levels.WARN)
        end
        return
    end

    if node.type ~= "commit" then return end

    -- Toggle expand/collapse for commit files
    if node:has_children() then
        if node:is_expanded() then
            node:collapse()
        else
            node:expand()
        end
        tree:render()
        return
    end

    -- Lazy-load files for this commit
    local ctx = require("UNX.context.uproject").get()
    local cwd = ctx.project_root or vim.fn.getcwd()

    vcs.get_commit_files(cwd, node.data, function(files)
        if not files or #files == 0 then return end

        local children = {}
        for _, f in ipairs(files) do
            table.insert(children, Tree.Node({
                text = f,
                id = "my_file_" .. node.data.hash .. "_" .. f,
                type = "file",
                data = { path = f, commit = node.data },
            }))
        end

        tree:set_nodes(children, node:get_id())
        node:expand()
        tree:render()
    end)
end

return M

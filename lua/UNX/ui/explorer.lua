-- lua/UNX/ui/explorer.lua
local Split = require("nui.split")
local Layout = require("nui.layout")

-- Viewモジュール
local ViewUproject = require("UNX.ui.view.uproject")
local ViewSymbols = require("UNX.ui.view.symbols")

local M = {}
local config = {}

local state = {
    layout = nil,
    uproject_split = nil,
    class_func_split = nil,
    uproject_tree = nil,
    class_func_tree = nil,
    augroup = vim.api.nvim_create_augroup("UNX_Explorer", { clear = true }),
}

function M.setup(opts)
    config = opts or {}
    
    ViewUproject.setup(config)
    ViewSymbols.setup(config)
    
    -- 自動更新イベント
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
        group = state.augroup,
        callback = function(args)
            local ft = vim.bo.filetype
            if ft ~= "c" and ft ~= "cpp" then return end

            if state.class_func_split and state.class_func_split.winid and vim.api.nvim_win_is_valid(state.class_func_split.winid) then
                local is_force = (args.event == "BufWritePost")
                ViewSymbols.update(state.class_func_tree, state.class_func_split.winid, { force = is_force })
            end
        end,
    })
end

function M.open()
    if state.layout and state.class_func_split and state.class_func_split.winid and vim.api.nvim_win_is_valid(state.class_func_split.winid) then
        vim.api.nvim_set_current_win(state.uproject_split.winid)
        return
    end

    local win_options = {
        number = false, relativenumber = false, wrap = false,
        signcolumn = "no", foldcolumn = "0", list = false, spell = false, winfixwidth = true,
    }
    local buf_options = { buftype = "nofile", swapfile = false, filetype = "unx-explorer", modifiable = false }

    state.uproject_split = Split({ enter = true, win_options = win_options, buf_options = buf_options })
    state.class_func_split = Split({ enter = false, win_options = win_options, buf_options = buf_options })

    local pos = config.window and config.window.position or "left"
    local sz = config.window and config.window.size or { width = 30 }
    state.layout = Layout({ position = pos, size = sz, relative = "editor" },
        Layout.Box({
            Layout.Box(state.uproject_split, { size = "60%" }),
            Layout.Box(state.class_func_split, { size = "40%" }),
        }, { dir = "col" })
    )
    state.layout:mount()

    if vim.fn.has("nvim-0.8") == 1 then
        vim.api.nvim_win_set_option(state.uproject_split.winid, "winbar", "%#UNXDirectoryIcon#  Project Tree")
        vim.api.nvim_win_set_option(state.class_func_split.winid, "winbar", "%#UNXGitFunction# 󰌗 Class/Function")
    end

    state.uproject_tree = ViewUproject.create(state.uproject_split.bufnr)
    state.class_func_tree = ViewSymbols.create(state.class_func_split.bufnr)
    
    state.uproject_tree:render()
    
    -- 初回表示時は強制更新
    if vim.bo.filetype == "c" or vim.bo.filetype == "cpp" then
        ViewSymbols.update(state.class_func_tree, state.class_func_split.winid, { force = true })
    end

    local function map_quit(split)
        for _, key in ipairs(config.keymaps.close or {"q"}) do
            split:map("n", key, function() state.layout:unmount() end, { noremap = true })
        end
    end
    map_quit(state.uproject_split)
    map_quit(state.class_func_split)

    -- Enterキーのマッピング
    for _, key in ipairs(config.keymaps.open or {"<CR>"}) do
        state.uproject_split:map("n", key, function()
            ViewUproject.on_node_action(state.uproject_tree, state.uproject_split, state.class_func_split)
        end)
        
        state.class_func_split:map("n", key, function()
            ViewSymbols.on_node_action(state.class_func_tree, state.class_func_split, state.uproject_split)
        end)
    end

    -- ★ マウス操作のマッピング (ダブルクリックで実行)
    local function map_mouse(split, tree, view_mod)
        split:map("n", "<2-LeftMouse>", function()
            local mouse = vim.fn.getmousepos()
            if mouse.winid == split.winid then
                vim.api.nvim_set_current_win(mouse.winid)
                vim.api.nvim_win_set_cursor(mouse.winid, {mouse.line, 0})
                view_mod.on_node_action(tree, state.uproject_split, state.class_func_split)
            end
        end)
    end
    
    map_mouse(state.uproject_split, state.uproject_tree, ViewUproject)
    map_mouse(state.class_func_split, state.class_func_tree, ViewSymbols)
end

function M.refresh()
    ViewUproject.refresh(state.uproject_tree)
end

return M

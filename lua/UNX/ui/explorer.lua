local Split = require("nui.split")
local Layout = require("nui.layout")

-- ★ Viewモジュールをロード
local ViewUproject = require("UNX.ui.view.uproject")
local ViewSymbols = require("UNX.ui.view.symbols")

local M = {}
local config = {}

-- 状態保持用
local state = {
    layout = nil,
    uproject_split = nil,
    class_func_split = nil,
    uproject_tree = nil,
    class_func_tree = nil,
    augroup = vim.api.nvim_create_augroup("UNX_Explorer", { clear = true }),
}

-- ======================================================
-- MAIN LOGIC
-- ======================================================

function M.setup(opts)
    config = opts or {}
    
    -- 各ビューに設定を伝播
    ViewUproject.setup(config)
    ViewSymbols.setup(config)
    
    -- 自動更新イベント (Symbols View用)
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
        group = state.augroup,
        callback = function()
            -- 修正: layout.winid ではなく、実際のコンポーネント(class_func_split)のウィンドウIDをチェックする
            if state.class_func_split and state.class_func_split.winid and vim.api.nvim_win_is_valid(state.class_func_split.winid) then
                -- print("[UNX-AUTO] Triggering update for winid: " .. tostring(state.class_func_split.winid)) -- デバッグ用
                ViewSymbols.update(state.class_func_tree, state.class_func_split.winid)
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

    -- Split コンポーネント作成
    state.uproject_split = Split({ enter = true, win_options = win_options, buf_options = buf_options })
    state.class_func_split = Split({ enter = false, win_options = win_options, buf_options = buf_options })

    -- Layout 作成
    local pos = config.window and config.window.position or "left"
    local sz = config.window and config.window.size or { width = 30 }
    state.layout = Layout({ position = pos, size = sz, relative = "editor" },
        Layout.Box({
            Layout.Box(state.uproject_split, { size = "60%" }),
            Layout.Box(state.class_func_split, { size = "40%" }),
        }, { dir = "col" })
    )
    state.layout:mount()

    -- WinBar 初期設定
    if vim.fn.has("nvim-0.8") == 1 then
        vim.api.nvim_win_set_option(state.uproject_split.winid, "winbar", "%#UNXDirectoryIcon#  Project Tree")
        vim.api.nvim_win_set_option(state.class_func_split.winid, "winbar", "%#UNXGitFunction# 󰌗 Class/Function")
    end

    -- Tree インスタンス作成 (各ビューモジュールに委譲)
    state.uproject_tree = ViewUproject.create(state.uproject_split.bufnr)
    state.class_func_tree = ViewSymbols.create(state.class_func_split.bufnr)
    
    -- 初回表示
    state.uproject_tree:render()
    
    -- ★修正: 初回はカレントバッファ（UNXを開く直前にいたバッファ）を対象にするため、少し遅延させるか明示的に取得
    -- ただし open 直後はフォーカスが UNX に移っているため、直前のウィンドウのバッファを取得するのが理想
    -- ここではシンプルに update を呼ぶ（開いた直後の update は unx-explorer なので無視されるが、戻った時に BufEnter が走る）
    ViewSymbols.update(state.class_func_tree, state.class_func_split.winid)

    -- キーマップ設定: 終了
    local function map_quit(split)
        for _, key in ipairs(config.keymaps.close or {"q"}) do
            split:map("n", key, function() state.layout:unmount() end, { noremap = true })
        end
    end
    map_quit(state.uproject_split)
    map_quit(state.class_func_split)

    -- キーマップ設定: 各ビューのアクション
    for _, key in ipairs(config.keymaps.open or {"<CR>"}) do
        state.uproject_split:map("n", key, function()
            ViewUproject.on_node_action(state.uproject_tree, state.uproject_split, state.class_func_split)
        end)
        
        state.class_func_split:map("n", key, function()
            ViewSymbols.on_node_action(state.class_func_tree, state.class_func_split, state.uproject_split)
        end)
    end
end

function M.refresh()
    ViewUproject.refresh(state.uproject_tree)
end

return M

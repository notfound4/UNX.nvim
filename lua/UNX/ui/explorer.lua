-- lua/UNX/ui/explorer.lua

-- NuiのLayout/Splitは使用せず、Tree(描画)だけ使う
local Tree = require("nui.tree")
local Line = require("nui.line")

-- Viewモジュール
local ViewUproject = require("UNX.ui.view.uproject")
local ViewSymbols = require("UNX.ui.view.symbols")
local ViewInsights = require("UNX.ui.view.insights")

local M = {}
local config = {}

-- 前方宣言
local switch_layout 
local handle_tab_switch_click 

-- 状態管理
local state = {
    -- バッファID (作成時に保持し続ける)
    buf_uproject = nil,
    buf_symbols = nil,
    buf_insights = nil,

    -- ウィンドウID (動的に変わる)
    win_main = nil,   -- 上側 (Project または Insights)
    win_sub = nil,    -- 下側 (Symbols)

    -- 現在のモード
    current_tab = "uproject", -- "uproject" or "insights"

    -- Treeインスタンス
    uproject_tree = nil,
    class_func_tree = nil,
    insights_tree = nil,
}

-- ======================================================
-- WINDOW / BUFFER UTILS
-- ======================================================

-- 専用バッファを作成または取得する関数
local function get_or_create_buffer(buf_handle_name, filetype)
    local buf = state[buf_handle_name]
    if buf and vim.api.nvim_buf_is_valid(buf) then
        return buf
    end

    buf = vim.api.nvim_create_buf(false, true) -- nofile, listed
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].filetype = filetype or "unx-explorer"
    vim.bo[buf].modifiable = false
    
    state[buf_handle_name] = buf
    return buf
end

-- ウィンドウ設定を適用
local function apply_window_options(winid)
    if not winid or not vim.api.nvim_win_is_valid(winid) then return end
    local opts = {
        number = false, relativenumber = false, wrap = false,
        signcolumn = "no", foldcolumn = "0", list = false, spell = false, 
        winfixwidth = true
    }
    for k, v in pairs(opts) do
        vim.wo[winid][k] = v
    end
end

-- ======================================================
-- KEYMAPS & ACTIONS
-- ======================================================

local function apply_buffer_keymaps(bufnr, tab_name)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

    local opts = { noremap = true, silent = true, buffer = bufnr }

    -- 1. Tab切り替え
    vim.keymap.set("n", "<Tab>", function()
        local target = (state.current_tab == "uproject") and "insights" or "uproject"
        switch_layout(target)
    end, opts)

    -- 2. マウスクリック (Tab切り替え)
    vim.keymap.set("n", "<LeftMouse>", function()
        local winid = vim.api.nvim_get_current_win()
        local mouse_line = vim.fn.getmousepos().line
        if mouse_line == 0 or mouse_line == 1 then
            handle_tab_switch_click(winid)
        end
    end, opts)
    
    -- 3. マウスダブルクリック (アクション)
    vim.keymap.set("n", "<2-LeftMouse>", function()
        local winid = vim.api.nvim_get_current_win()
        local mouse = vim.fn.getmousepos()
        if mouse.winid ~= winid or mouse.line <= 1 then return end
        
        vim.api.nvim_set_current_win(winid)
        pcall(vim.api.nvim_win_set_cursor, winid, {mouse.line, 0})
        
        -- バッファに応じたアクションを実行
        if bufnr == state.buf_uproject then
            ViewUproject.on_node_action(state.uproject_tree, nil, nil)
        elseif bufnr == state.buf_symbols then
            ViewSymbols.on_node_action(state.class_func_tree, nil, nil)
        elseif bufnr == state.buf_insights then
            ViewInsights.on_node_action(state.insights_tree, nil, nil)
        end
    end, opts)

    -- 4. エンターキー (アクション)
    local keys = config.keymaps.open or {"<CR>", "o"}
    for _, key in ipairs(keys) do
        vim.keymap.set("n", key, function()
            if bufnr == state.buf_uproject then
                ViewUproject.on_node_action(state.uproject_tree, nil, nil)
            elseif bufnr == state.buf_symbols then
                ViewSymbols.on_node_action(state.class_func_tree, nil, nil)
            elseif bufnr == state.buf_insights then
                ViewInsights.on_node_action(state.insights_tree, nil, nil)
            end
        end, opts)
    end

    -- 5. 閉じる (UNX close)
    local close_keys = config.keymaps.close or {"q"}
    for _, key in ipairs(close_keys) do
        vim.keymap.set("n", key, function() M.close() end, opts)
    end
end

-- ======================================================
-- LAYOUT & RENDERING
-- ======================================================

local function update_winbars()
    -- WinBar文字列生成
    local hl_active   = "%#UNXTabActive#"
    local hl_inactive = "%#UNXTabInactive#"
    local hl_sep      = "%#UNXTabSeparator#"
    local text_sep    = " | "

    -- Main Window (Uproject or Insights)
    if state.win_main and vim.api.nvim_win_is_valid(state.win_main) then
        local bar_text = ""
        if state.current_tab == "uproject" then
            bar_text = hl_active .. " uproject" .. hl_sep .. text_sep .. hl_inactive .. " insights"
        else
            bar_text = hl_inactive .. " uproject" .. hl_sep .. text_sep .. hl_active .. " insights"
        end
        pcall(vim.api.nvim_win_set_option, state.win_main, "winbar", bar_text)
    end

    -- Sub Window (Symbols) - Symbolsが表示されている時のみ
    if state.win_sub and vim.api.nvim_win_is_valid(state.win_sub) then
        local buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
        local filename = vim.fn.fnamemodify(buf_name, ":t:r")
        if vim.bo[vim.api.nvim_get_current_buf()].filetype == "unx-explorer" then
            filename = "Symbols"
        end
        
        local sym_bar = "%#UNXGitFunction# 󰌗 Class/Function " .. filename
        pcall(vim.api.nvim_win_set_option, state.win_sub, "winbar", sym_bar)
    end
end

switch_layout = function(target_tab)
    if state.current_tab == target_tab then return end
    state.current_tab = target_tab

    -- ウィンドウが存在しない場合は何もしない（openで処理される）
    if not state.win_main or not vim.api.nvim_win_is_valid(state.win_main) then return end

    if target_tab == "uproject" then
        -- 1. Mainウィンドウを uproject バッファに切り替え
        vim.api.nvim_win_set_buf(state.win_main, state.buf_uproject)
        
        -- 2. Symbolsウィンドウが必要 (無ければ作る)
        if not state.win_sub or not vim.api.nvim_win_is_valid(state.win_sub) then
            local current_win = vim.api.nvim_get_current_win()
            vim.api.nvim_set_current_win(state.win_main)
            
            -- 40%の高さで分割
            vim.cmd("belowright split")
            local height = math.floor(vim.api.nvim_win_get_height(state.win_main) * 0.4)
            -- 高さが0にならないように保護
            if height < 1 then height = 1 end
            vim.cmd("resize " .. height)
            
            state.win_sub = vim.api.nvim_get_current_win()
            apply_window_options(state.win_sub)
            
            vim.api.nvim_set_current_win(state.win_main)
        end
        
        -- 3. Symbolsバッファをセット
        vim.api.nvim_win_set_buf(state.win_sub, state.buf_symbols)
        
        -- Tree更新
        if vim.bo.filetype:match("cpp") then
             ViewSymbols.update(state.class_func_tree, state.win_sub, { force = true })
        end

    elseif target_tab == "insights" then
        -- 1. Mainウィンドウを insights バッファに切り替え
        vim.api.nvim_win_set_buf(state.win_main, state.buf_insights)
        
        -- 2. Symbolsウィンドウがあれば閉じる
        if state.win_sub and vim.api.nvim_win_is_valid(state.win_sub) then
            pcall(vim.api.nvim_win_close, state.win_sub, true)
            state.win_sub = nil
        end
        
        -- Tree描画
        ViewInsights.render(state.insights_tree)
    end
    
    update_winbars()
end

handle_tab_switch_click = function(winid)
    -- WinBarクリック判定ロジック
    if winid ~= state.win_main then return end
    
    local mouse = vim.fn.getmousepos()
    local col = mouse.wincol
    if not col then return end
    
    local strwidth = vim.fn.strdisplaywidth
    local up_w = strwidth(" uproject ")
    local sep_w = strwidth(" | ")
    
    if col < up_w + 5 then
        switch_layout("uproject")
    elseif col > up_w + sep_w then
        switch_layout("insights")
    end
end


-- ======================================================
-- PUBLIC API
-- ======================================================

function M.setup(opts)
    config = opts or {}
    
    ViewUproject.setup(config)
    ViewSymbols.setup(config)
    ViewInsights.setup(config)

    -- UNL Event Subscribers
    local unl_api_ok, unl_api = pcall(require, "UNL.api")
    if unl_api_ok then
        local unl_types_ok, unl_event_types = pcall(require, "UNL.event.types")
        if unl_types_ok then
            require("UNL.event.events").subscribe(unl_event_types.ON_REQUEST_TRACE_CALLEES_VIEW, function(payload)
                if not M.is_open() then M.open() end
                switch_layout("insights")
                if state.insights_tree and payload and payload.frame_data then
                    ViewInsights.set_data(payload.trace_handle, payload.frame_data)
                end
            end)

            require("UNL.event.events").subscribe(unl_event_types.ON_REQUEST_UPROJECT_TREE_VIEW, function(payload)
                if not M.is_open() then M.open() end
                switch_layout("uproject")
                if state.uproject_tree then
                     ViewUproject.refresh(state.uproject_tree)
                end
            end)
        end
    end
    
    -- 自動更新イベント (Symbols)
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
        callback = function(args)
            local ft = vim.bo.filetype
            if ft ~= "c" and ft ~= "cpp" then return end
            -- メインタブがuprojectで、かつサブウィンドウが開いている時だけ更新
            if state.current_tab == "uproject" and state.win_sub and vim.api.nvim_win_is_valid(state.win_sub) then
                local is_force = (args.event == "BufWritePost")
                ViewSymbols.update(state.class_func_tree, state.win_sub, { force = is_force })
            end
        end,
    })
end

function M.open()
    -- 既に開いている場合はフォーカスして終了
    if state.win_main and vim.api.nvim_win_is_valid(state.win_main) then
        vim.api.nvim_set_current_win(state.win_main)
        return
    end

    -- 1. バッファの準備
    state.buf_uproject = get_or_create_buffer("buf_uproject")
    state.buf_symbols  = get_or_create_buffer("buf_symbols")
    state.buf_insights = get_or_create_buffer("buf_insights")
    
    apply_buffer_keymaps(state.buf_uproject, "uproject")
    apply_buffer_keymaps(state.buf_symbols, "uproject")
    apply_buffer_keymaps(state.buf_insights, "insights")

    -- 2. ウィンドウ作成 (★ここを修正)
    local width = config.window and config.window.size and config.window.size.width or 35
    local pos = config.window and config.window.position or "left"
    
    -- topleft / botright の決定
    local modifier = (pos == "right" and "botright" or "topleft")
    
    -- 安全な分割コマンド: まず分割し、そのあと幅を設定する
    vim.cmd(modifier .. " vsplit")
    state.win_main = vim.api.nvim_get_current_win()
    
    -- 幅を設定
    vim.api.nvim_win_set_width(state.win_main, width)
    
    apply_window_options(state.win_main)
    
    -- 3. Treeの初期化
    if not state.uproject_tree then
        state.uproject_tree = ViewUproject.create(state.buf_uproject, state.win_main)
    end
    if not state.class_func_tree then
        state.class_func_tree = ViewSymbols.create(state.buf_symbols)
    end
    if not state.insights_tree then
        state.insights_tree = ViewInsights.create(state.buf_insights)
    end

    -- 4. 初期レイアウト適用
    state.current_tab = nil 
    switch_layout("uproject")

    -- 5. データ描画
    ViewUproject.refresh(state.uproject_tree)
end

function M.close()
    local wins = { state.win_main, state.win_sub }
    for _, winid in ipairs(wins) do
        if winid and vim.api.nvim_win_is_valid(winid) then
            pcall(vim.api.nvim_win_close, winid, true)
        end
    end
    
    state.win_main = nil
    state.win_sub = nil
    state.current_tab = "uproject"
    
    ViewUproject.cancel_async_tasks()
end

function M.refresh()
    if state.uproject_tree and state.current_tab == "uproject" then
        ViewUproject.refresh(state.uproject_tree)
    end
end

function M.is_open()
    return state.win_main and vim.api.nvim_win_is_valid(state.win_main)
end

return M

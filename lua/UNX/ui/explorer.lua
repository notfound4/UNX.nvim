-- lua/UNX/ui/explorer.lua

local Tree = require("nui.tree")
local Line = require("nui.line")

-- Viewモジュール
local ViewUproject = require("UNX.ui.view.uproject")
local ViewSymbols = require("UNX.ui.view.symbols")
local ViewInsights = require("UNX.ui.view.insights")

-- コンテキスト (設定データの保存用)
local ctx_explorer = require("UNX.context.explorer")

local M = {}
local config = {}

local switch_layout 
local handle_tab_switch_click 

-- ★【重要】UIオブジェクトはローカル変数で管理する (Contextには入れない)
-- これらは関数を含むオブジェクトや、再起動で無効になるIDなので保存できません。
local ui = {
    buf_uproject = nil,
    buf_symbols = nil,
    buf_insights = nil,
    win_main = nil,
    win_sub = nil,
    uproject_tree = nil,
    class_func_tree = nil,
    insights_tree = nil,
}

-- ======================================================
-- HELPER: Context Access
-- ======================================================

-- 現在のタブ情報だけは Context (保存データ) から取得・保存する
local function get_current_tab()
    local state = ctx_explorer.get()
    return state.current_tab or "uproject"
end

local function set_current_tab(tab_name)
    local state = ctx_explorer.get()
    state.current_tab = tab_name
    ctx_explorer.set(state)
end

-- ======================================================
-- WINDOW / BUFFER UTILS
-- ======================================================

local function get_or_create_buffer(key, filetype)
    local buf = ui[key]
    if buf and vim.api.nvim_buf_is_valid(buf) then
        return buf
    end

    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].filetype = filetype or "unx-explorer"
    vim.bo[buf].modifiable = false
    
    ui[key] = buf
    return buf
end

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

local function apply_buffer_keymaps(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

    local opts = { noremap = true, silent = true, buffer = bufnr }

    -- 1. Tab切り替え
    vim.keymap.set("n", "<Tab>", function()
        local current = get_current_tab()
        local target = (current == "uproject") and "insights" or "uproject"
        switch_layout(target)
    end, opts)

    -- 2. マウスクリック
    vim.keymap.set("n", "<LeftMouse>", function()
        local winid = vim.api.nvim_get_current_win()
        local mouse_line = vim.fn.getmousepos().line
        if mouse_line == 0 or mouse_line == 1 then
            handle_tab_switch_click(winid)
        end
    end, opts)
    
    -- 3. アクション (Double Click / Enter)
    local function do_action()
        if bufnr == ui.buf_uproject then
            ViewUproject.on_node_action(ui.uproject_tree, nil, nil)
        elseif bufnr == ui.buf_symbols then
            ViewSymbols.on_node_action(ui.class_func_tree, nil, nil)
        elseif bufnr == ui.buf_insights then
            ViewInsights.on_node_action(ui.insights_tree, nil, nil)
        end
    end

    vim.keymap.set("n", "<2-LeftMouse>", function()
        local winid = vim.api.nvim_get_current_win()
        local mouse = vim.fn.getmousepos()
        if mouse.winid ~= winid or mouse.line <= 1 then return end
        vim.api.nvim_set_current_win(winid)
        pcall(vim.api.nvim_win_set_cursor, winid, {mouse.line, 0})
        do_action()
    end, opts)

    local keys = config.keymaps.open or {"<CR>", "o"}
    for _, key in ipairs(keys) do
        vim.keymap.set("n", key, do_action, opts)
    end

    local close_keys = config.keymaps.close or {"q"}
    for _, key in ipairs(close_keys) do
        vim.keymap.set("n", key, function() M.close() end, opts)
    end
end

-- ======================================================
-- LAYOUT & RENDERING
-- ======================================================

local function update_winbars()
    local current_tab = get_current_tab()
    local hl_active   = "%#UNXTabActive#"
    local hl_inactive = "%#UNXTabInactive#"
    local hl_sep      = "%#UNXTabSeparator#"
    local text_sep    = " | "

    if ui.win_main and vim.api.nvim_win_is_valid(ui.win_main) then
        local bar_text = ""
        if current_tab == "uproject" then
            bar_text = hl_active .. " uproject" .. hl_sep .. text_sep .. hl_inactive .. " insights"
        else
            bar_text = hl_inactive .. " uproject" .. hl_sep .. text_sep .. hl_active .. " insights"
        end
        pcall(vim.api.nvim_win_set_option, ui.win_main, "winbar", bar_text)
    end

    if ui.win_sub and vim.api.nvim_win_is_valid(ui.win_sub) then
        local buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
        local filename = vim.fn.fnamemodify(buf_name, ":t:r")
        if vim.bo[vim.api.nvim_get_current_buf()].filetype == "unx-explorer" then
            filename = "Symbols"
        end
        local sym_bar = "%#UNXGitFunction# 󰌗 Class/Function " .. filename
        pcall(vim.api.nvim_win_set_option, ui.win_sub, "winbar", sym_bar)
    end
end

switch_layout = function(target_tab)
    local current = get_current_tab()
    if current ~= target_tab then
        set_current_tab(target_tab)
    end

    if not ui.win_main or not vim.api.nvim_win_is_valid(ui.win_main) then return end

    if target_tab == "uproject" then
        vim.api.nvim_win_set_buf(ui.win_main, ui.buf_uproject)
        
        if not ui.win_sub or not vim.api.nvim_win_is_valid(ui.win_sub) then
            local current_win = vim.api.nvim_get_current_win()
            vim.api.nvim_set_current_win(ui.win_main)
            
            vim.cmd("belowright split")
            local height = math.floor(vim.api.nvim_win_get_height(ui.win_main) * 0.4)
            if height < 1 then height = 1 end
            vim.cmd("resize " .. height)
            
            ui.win_sub = vim.api.nvim_get_current_win()
            apply_window_options(ui.win_sub)
            vim.api.nvim_set_current_win(ui.win_main)
        end
        
        vim.api.nvim_win_set_buf(ui.win_sub, ui.buf_symbols)
        
        if vim.bo.filetype:match("cpp") then
             ViewSymbols.update(ui.class_func_tree, ui.win_sub, { force = true })
        end

    elseif target_tab == "insights" then
        vim.api.nvim_win_set_buf(ui.win_main, ui.buf_insights)
        
        if ui.win_sub and vim.api.nvim_win_is_valid(ui.win_sub) then
            pcall(vim.api.nvim_win_close, ui.win_sub, true)
            ui.win_sub = nil
        end
        
        ViewInsights.render(ui.insights_tree)
    end
    
    update_winbars()
end

handle_tab_switch_click = function(winid)
    if winid ~= ui.win_main then return end
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

    local unl_api_ok, unl_api = pcall(require, "UNL.api")
    if unl_api_ok then
        local unl_types_ok, unl_event_types = pcall(require, "UNL.event.types")
        if unl_types_ok then
            require("UNL.event.events").subscribe(unl_event_types.ON_REQUEST_TRACE_CALLEES_VIEW, function(payload)
                if not M.is_open() then M.open() end
                switch_layout("insights")
                if ui.insights_tree and payload and payload.frame_data then
                    ViewInsights.set_data(payload.trace_handle, payload.frame_data)
                end
            end)

            require("UNL.event.events").subscribe(unl_event_types.ON_REQUEST_UPROJECT_TREE_VIEW, function(payload)
                if not M.is_open() then M.open() end
                switch_layout("uproject")
                if ui.uproject_tree then
                     ViewUproject.refresh(ui.uproject_tree)
                end
            end)
        end
    end
    
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
        callback = function(args)
            local ft = vim.bo.filetype
            if ft ~= "c" and ft ~= "cpp" then return end
            local current_tab = get_current_tab()
            if current_tab == "uproject" and ui.win_sub and vim.api.nvim_win_is_valid(ui.win_sub) then
                local is_force = (args.event == "BufWritePost")
                ViewSymbols.update(ui.class_func_tree, ui.win_sub, { force = is_force })
            end
        end,
    })
end

function M.open()
    if ui.win_main and vim.api.nvim_win_is_valid(ui.win_main) then
        vim.api.nvim_set_current_win(ui.win_main)
        return
    end

    -- 1. バッファの準備
    ui.buf_uproject = get_or_create_buffer("buf_uproject")
    ui.buf_symbols  = get_or_create_buffer("buf_symbols")
    ui.buf_insights = get_or_create_buffer("buf_insights")
    
    apply_buffer_keymaps(ui.buf_uproject)
    apply_buffer_keymaps(ui.buf_symbols)
    apply_buffer_keymaps(ui.buf_insights)

    -- 2. ウィンドウ作成
    local width = config.window and config.window.size and config.window.size.width or 35
    local pos = config.window and config.window.position or "left"
    local modifier = (pos == "right" and "botright" or "topleft")
    
    vim.cmd(modifier .. " vsplit")
    ui.win_main = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(ui.win_main, width)
    apply_window_options(ui.win_main)
    
    -- 3. Treeの初期化
    if not ui.uproject_tree then
        ui.uproject_tree = ViewUproject.create(ui.buf_uproject, ui.win_main)
    end
    if not ui.class_func_tree then
        ui.class_func_tree = ViewSymbols.create(ui.buf_symbols)
    end
    if not ui.insights_tree then
        ui.insights_tree = ViewInsights.create(ui.buf_insights)
    end

    -- 4. レイアウト適用 (Contextから前回のタブ設定を読み込む)
    local saved_tab = get_current_tab()
    -- 強制的にレイアウト処理を走らせるため、一時的にnilセットなどは不要。
    -- switch_layout内の current check で弾かれないよう注意するが、
    -- 初期状態のUIは空なので問題ない。
    switch_layout(saved_tab)

    -- 5. データ描画
    ViewUproject.refresh(ui.uproject_tree)
end

function M.close()
    local wins = { ui.win_main, ui.win_sub }
    for _, winid in ipairs(wins) do
        if winid and vim.api.nvim_win_is_valid(winid) then
            pcall(vim.api.nvim_win_close, winid, true)
        end
    end
    
    ui.win_main = nil
    ui.win_sub = nil
    
    ViewUproject.cancel_async_tasks()
end

function M.refresh()
    local current = get_current_tab()
    if ui.uproject_tree and current == "uproject" then
        ViewUproject.refresh(ui.uproject_tree)
    end
end

function M.is_open()
    return ui.win_main and vim.api.nvim_win_is_valid(ui.win_main)
end

return M

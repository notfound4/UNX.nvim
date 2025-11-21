-- lua/UNX/ui/explorer.lua

local Split = require("nui.split")
local Layout = require("nui.layout")

-- Viewモジュール
local ViewUproject = require("UNX.ui.view.uproject")
local ViewSymbols = require("UNX.ui.view.symbols")
local ViewInsights = require("UNX.ui.view.insights")

local M = {}
local config = {}

-- ★修正: switch_layout と handle_tab_switch_click の前方宣言を追加
local switch_layout 
local handle_tab_switch_click 

local state = {
    uproject_layout = nil,
    insights_layout = nil,
    current_layout = nil,
    
    uproject_split = nil,
    class_func_split = nil,
    insights_split = nil, 
    
    uproject_tree = nil,
    class_func_tree = nil,
    insights_tree = nil,
    augroup = vim.api.nvim_create_augroup("UNX_Explorer", { clear = true }),
}

-- ======================================================
-- HELPER FUNCTIONS (キーマップ, WINBAR, SWITCH)
-- ======================================================

local function apply_split_keymaps(uproject_split, class_func_split, insights_split)
    
    local function map_tab_and_mouse(split, is_uproject_tab)
        -- Tab/Mouse 切り替えマッピング
        local target_layout = is_uproject_tab and state.insights_layout or state.uproject_layout
        local target_split = is_uproject_tab and state.insights_split or state.uproject_split
        
        -- Tab キーマッピングの再適用
        pcall(split.unmap, split, "n", "<Tab>") 
        split:map("n", "<Tab>", function() 
            switch_layout(target_layout, target_split) 
        end, { noremap = true })
        
        -- マウスクリックマッピングの再適用
        pcall(split.unmap, split, "n", "<LeftMouse>")
        split:map("n", "<LeftMouse>", function() 
            local mouse_line = vim.fn.getmousepos().line
            if mouse_line == 0 or mouse_line == 1 then
                handle_tab_switch_click(split.winid)
            end
        end, { noremap = true })
    end
    
    local function map_node_action(split)
        for _, key in ipairs(config.keymaps.open or {"<CR>"}) do
             pcall(split.unmap, split, "n", key)
             split:map("n", key, function()
                if vim.api.nvim_get_current_win() == state.uproject_split.winid then
                    ViewUproject.on_node_action(state.uproject_tree, state.uproject_split, state.class_func_split)
                elseif vim.api.nvim_get_current_win() == state.class_func_split.winid then
                    ViewSymbols.on_node_action(state.class_func_tree, state.class_func_split, state.uproject_split)
                elseif vim.api.nvim_get_current_win() == state.insights_split.winid then
                    ViewInsights.on_node_action(state.insights_tree, state.insights_split, nil)
                end
            end)
        end
    end
    
local function map_mouse_action_dclick(split)
        pcall(split.unmap, split, "n", "<2-LeftMouse>")
        split:map("n", "<2-LeftMouse>", function()
            local mouse = vim.fn.getmousepos()
            if mouse.winid == split.winid then
                
                -- マウスが1行目（ウィンドウバー）をクリックした場合は処理をスキップ
                if mouse.line <= 1 then
                    return
                end
                
                vim.api.nvim_set_current_win(mouse.winid)
                
                -- ★修正: カーソルをマウスの位置に移動させるロジックを復活させる
                -- pcallで保護し、万が一のカーソルエラーを回避
                pcall(vim.api.nvim_win_set_cursor, mouse.winid, {mouse.line, 0})
                
                -- ノードアクションの実行
                if vim.api.nvim_get_current_win() == state.uproject_split.winid then
                    ViewUproject.on_node_action(state.uproject_tree, state.uproject_split, state.class_func_split)
                elseif vim.api.nvim_get_current_win() == state.class_func_split.winid then
                    ViewSymbols.on_node_action(state.class_func_tree, state.class_func_split, state.uproject_split)
                elseif vim.api.nvim_get_current_win() == state.insights_split.winid then
                    ViewInsights.on_node_action(state.insights_tree, state.insights_split, nil)
                end
            end
        end)
    end


    map_tab_and_mouse(uproject_split, true)
    map_tab_and_mouse(class_func_split, true)
    map_tab_and_mouse(insights_split, false)

    map_node_action(uproject_split)
    map_node_action(class_func_split)
    map_node_action(insights_split)
    
    -- ★修正: ダブルクリックマッピングを有効化
    map_mouse_action_dclick(uproject_split)
    map_mouse_action_dclick(class_func_split)
    map_mouse_action_dclick(insights_split)
    
    -- Quit keymap (省略)
    for _, key in ipairs(config.keymaps.close or {"q"}) do
        uproject_split:map("n", key, function() state.current_layout:unmount() end, { noremap = true })
        class_func_split:map("n", key, function() state.current_layout:unmount() end, { noremap = true })
        insights_split:map("n", key, function() state.current_layout:unmount() end, { noremap = true })
    end
end


local function update_winbars(active_layout)
    local tab_uproject_active = "%#UNXGitAdded# uproject %#UNXGitModified# | "
    local tab_uproject_inactive = "%#UNXGitIgnored# uproject | "
    local tab_insights_active = "%#UNXGitAdded# insights"
    local tab_insights_inactive = "%#UNXGitIgnored# insights"
    
    local uproject_prefix = "" 
    local symbols_prefix = "%#UNXGitFunction# 󰌗 Class/Function " 
    local insights_prefix = ""

    local buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    
    -- 正しい関数名 vim.fn.fnamemodify を使用
    local filename = vim.fn.fnamemodify(buf_name, ":t:r") 

    if active_layout == state.uproject_layout then
        local up_bar = uproject_prefix .. tab_uproject_active .. tab_insights_inactive
        pcall(vim.api.nvim_win_set_option, state.uproject_split.winid, "winbar", up_bar)
        
        local sym_bar = symbols_prefix .. filename
        pcall(vim.api.nvim_win_set_option, state.class_func_split.winid, "winbar", sym_bar)
        
    elseif active_layout == state.insights_layout then
        local insight_bar = insights_prefix .. tab_uproject_inactive .. tab_insights_active
        pcall(vim.api.nvim_win_set_option, state.insights_split.winid, "winbar", insight_bar)
    end
end


handle_tab_switch_click = function(winid)
    local mouse = vim.fn.getmousepos()
    
    -- 行 0 (Winbar) または 1 (バッファの最初の行) でない場合はスキップ
    if mouse.winid ~= winid or (mouse.line ~= 0 and mouse.line ~= 1) then 
        return 
    end
    
    -- ★修正: mouse.col ではなく、有効な値が入っている mouse.wincol を使用
local col = mouse.wincol 
    
    if col == nil then
        vim.notify("UNX Error: Mouse wincol position is nil. Tab switch ignored.", vim.log.levels.WARN)
        return
    end
    
    local target_layout = nil
    local target_split = nil

    -- ★修正: ここでクリック範囲を動的に計算する
    local strwidth = vim.fn.strdisplaywidth

    -- 1. uproject tab の幅計算
    local up_tab_width = strwidth("uproject")
    local up_start = 1
    local up_end = up_start + up_tab_width

    -- 2. insights tab の幅計算
    local sep_width = strwidth(" | ")
    local ins_tab_width = strwidth("insights")
    local ins_start = up_end + sep_width + 1 -- up_end の次の列 + セパレータ + 1-basedの調整
    local ins_end = ins_start + ins_tab_width - 1
    
    -- ★prefix が有効な場合は up_start を調整する必要がある (今回は空なので 1 のまま)

    -- クリック判定
    if col >= up_start and col <= up_end then
        target_layout = state.uproject_layout
        target_split = state.uproject_split
    elseif col >= ins_start and col <= ins_end then
        target_layout = state.insights_layout
        target_split = state.insights_split
    end
    
    if target_layout then
        local ok, err = pcall(switch_layout, target_layout, target_split)
        if not ok then
            vim.notify("UNX Error: Tab switch failed - " .. tostring(err), vim.log.levels.ERROR)
        end
    end
end


switch_layout = function(new_layout, target_split)
    if state.current_layout == new_layout then return end

    -- 1. 現在のアクティブなレイアウトを隠す
    if state.current_layout then
        if state.current_layout == state.uproject_layout then
            ViewUproject.cancel_async_tasks()
        end
        
        -- ★修正: unmount ではなく hide を使用して、インスタンスを保持する
        state.current_layout:hide() 
    end
    
    -- 2. 新しいレイアウトをマウント（表示）する
    state.current_layout = new_layout
    state.current_layout:show() -- mount/show を使用

    -- 3. 後処理（winbar更新とフォーカス）
    if target_split and target_split.winid and vim.api.nvim_win_is_valid(target_split.winid) then
        local target_winid = target_split.winid
        
        vim.api.nvim_set_current_win(target_winid)
        update_winbars(new_layout)
        
        if new_layout == state.insights_layout then
            ViewInsights.render(state.insights_tree)
        end
    end
    
    if new_layout == state.uproject_layout and vim.bo.filetype:match("cpp") then
       ViewSymbols.update(state.class_func_tree, state.class_func_split.winid, { force = true })
    end
    
    -- ★重要: キーマップの再適用ロジックは不要になるはずです（インスタンスが生きているため）
end


-- ======================================================
-- PUBLIC API (SETUP & OPEN)
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
            -- ULGからのON_REQUEST_TRACE_CALLEES_VIEW イベントを監視
            require("UNL.event.events").subscribe(unl_event_types.ON_REQUEST_TRACE_CALLEES_VIEW, function(payload)
                -- Insightsタブが非アクティブな場合は自動で切り替える
                if state.current_layout ~= state.insights_layout then
                    switch_layout(state.insights_layout, state.insights_split)
                end
                
                if state.insights_tree and payload and payload.frame_data then
                    -- ViewInsightsにデータを渡し、描画を要求する
                    ViewInsights.set_data(payload.trace_handle, payload.frame_data)
                end
            end)

          -- ★★★ 追記: UEP ON_REQUEST_UPROJECT_TREE_VIEW イベントの監視 ★★★
            require("UNL.event.events").subscribe(unl_event_types.ON_REQUEST_UPROJECT_TREE_VIEW, function(payload)
                local log = require("UNX.logger").get()
                log.info("Received ON_REQUEST_UPROJECT_TREE_VIEW event from UEP.")
                
                -- 1. UNXウィンドウが開いていなければ開く
                if not (state.uproject_split and state.uproject_split.winid and vim.api.nvim_win_is_valid(state.uproject_split.winid)) then
                    M.open()
                    -- M.open() が非同期的にツリーを構築するため、ここではツリーの再描画は行わない
                end

                -- 2. uprojectレイアウトに切り替え、フォーカスする
                switch_layout(state.uproject_layout, state.uproject_split)
                
                -- 3. 強制リフレッシュをスケジュール
                -- (新しいペイロードは次回UNXがノードを遅延ロードするときに自動で取得されるため、ここでは強制リフレッシュだけでOK)
                if state.uproject_tree then
                     ViewUproject.refresh(state.uproject_tree)
                     -- Note: ViewUproject.refresh の中で UEP.build_tree_model をリクエストする必要がある。
                     -- 現状の ViewUproject.refresh は fetch_root_data() を呼ぶが、これは pending request を無視するため、
                     -- UEPとUNXを統合するなら ViewUproject のロジック全体を見直す必要があります。
                     -- **今回は、M.refresh()を呼び出すことで、次回描画時に pending request を参照できることを期待します。**
                end
            end)
            -- ★★★ 追記ここまで ★★★

        end
    end

    -- 自動更新イベント
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
        group = state.augroup,
        callback = function(args)
            local ft = vim.bo.filetype
            if ft ~= "c" and ft ~= "cpp" then return end

            if state.current_layout == state.uproject_layout and state.class_func_split and state.class_func_split.winid and vim.api.nvim_win_is_valid(state.class_func_split.winid) then
                local is_force = (args.event == "BufWritePost")
                ViewSymbols.update(state.class_func_tree, state.class_func_split.winid, { force = is_force })
            end
        end,
    })
end

function M.open()
    if state.uproject_split and state.uproject_split.winid and vim.api.nvim_win_is_valid(state.uproject_split.winid) then
        vim.api.nvim_set_current_win(state.uproject_split.winid)
        return
    end

    local win_options = {
        number = false, relativenumber = false, wrap = false,
        signcolumn = "no", foldcolumn = "0", list = false, spell = false, winfixwidth = true,
    }
    local buf_options = { buftype = "nofile", swapfile = false, filetype = "unx-explorer", modifiable = false }

    -- 1. Tab 1: Uproject & Symbols のレイアウト構築
    local up_split = Split({ enter = true, win_options = win_options, buf_options = buf_options })
    local cf_split = Split({ enter = false, win_options = win_options, buf_options = buf_options })
    
    if not up_split or not up_split.mount or not cf_split or not cf_split.mount then
        vim.notify("UNX Error: Failed to create Split instances for Project/Symbols.", vim.log.levels.ERROR)
        return
    end

    state.uproject_split = up_split
    state.class_func_split = cf_split
    
    local pos = config.window and config.window.position or "left"
    local sz = config.window and config.window.size or { width = 30 }

    state.uproject_layout = Layout({ position = pos, size = sz, relative = "editor" },
        Layout.Box({
            Layout.Box(state.uproject_split, { size = "60%" }),
            Layout.Box(state.class_func_split, { size = "40%" }),
        }, { dir = "col" })
    )
    
    -- 2. Tab 2: Insights のレイアウト構築
    local ins_split = Split({ enter = false, win_options = win_options, buf_options = buf_options })
    
    if not ins_split or not ins_split.mount then
        vim.notify("UNX Error: Failed to create valid Insights Split instance.", vim.log.levels.ERROR)
        return 
    end
    
    state.insights_split = ins_split
    
    state.insights_layout = Layout({ position = pos, size = sz, relative = "editor" },
        Layout.Box({ 
            Layout.Box(state.insights_split, { size = "100%" })
        })
    )
    
    -- mount前にキーマップを初期適用 (mount時にキーマップが有効になるように)
    apply_split_keymaps(state.uproject_split, state.class_func_split, state.insights_split)
    
    state.uproject_layout:mount()
    state.current_layout = state.uproject_layout

    if vim.fn.has("nvim-0.8") == 1 then
        update_winbars(state.uproject_layout)
    end

    -- Treeインスタンスの作成
    state.uproject_tree = ViewUproject.create(state.uproject_split.bufnr, state.uproject_split.winid)
    state.class_func_tree = ViewSymbols.create(state.class_func_split.bufnr)
    state.insights_tree = ViewInsights.create(state.insights_split.bufnr)

    state.uproject_tree:render()
    
    if vim.bo.filetype == "c" or vim.bo.filetype == "cpp" then
       ViewSymbols.update(state.class_func_tree, state.class_func_split.winid, { force = true })
    end
end

function M.refresh()
    if state.uproject_tree and state.current_layout == state.uproject_layout then
        ViewUproject.refresh(state.uproject_tree)
    end
end

return M

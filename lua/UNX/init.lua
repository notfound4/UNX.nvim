local M = {}

-- UNLのロギングモジュール
local unl_log = require("UNL.logging")

local function setup_highlights(highlights)
    -- ハイライト設定がnilの場合はガードしてクラッシュを防ぐ
    if not highlights then return end

    for group, opts in pairs(highlights) do
        opts.default = true
        vim.api.nvim_set_hl(0, group, opts)
    end
end

function M.setup(user_config)
    -- VCSモジュールを読み込み
    local unx_vcs = require("UNX.vcs")

    -- デフォルト設定とユーザー設定をマージ
    local default_config = require("UNX.config.defaults")
    local config = vim.tbl_deep_extend("force", default_config, user_config or {})
    
    -- 1. ロガー初期化
    unl_log.setup("UNX", default_config, user_config)
    
    -- 2. プロバイダー登録 (UNLへの登録)
    require("UNX.provider.init").setup()
    
    -- 3. ハイライト設定
    -- ★修正: ここではマージ済みのローカル変数 'config' を使うことで nil エラーを回避
    setup_highlights(config.highlights)
    
    -- 4. Explorer UI セットアップ
    require("UNX.ui.explorer").setup(config)


    -- ============================================================
    --  自動チェックアウト機能 (Auto Checkout)
    -- ============================================================
    local group = vim.api.nvim_create_augroup("UNX_AutoCheckout", { clear = true })
    
    local function try_checkout(buf, filepath)
        -- ★ 重要: 実行時に UNL.config から設定を取得する
        -- これにより、プロジェクトルートの .unlrc.json で "auto_checkout": false になっていれば
        -- それが反映されます。
        local conf = require("UNL.config").get("UNX")
        
        -- 設定チェック: vcs.p4.auto_checkout が有効か？
        -- (設定がない、または明示的に false の場合は何もしない)
        if not (conf.vcs and conf.vcs.p4 and conf.vcs.p4.enabled and conf.vcs.p4.auto_checkout) then
            return 
        end

        -- ファイルが存在しない場合は無視
        if vim.fn.filereadable(filepath) == 0 then return end
        
        -- ★ P4管理ファイルでなければ即終了 (無視)
        -- node_modules や システムファイルでダイアログが出るのを防ぐ
        if not unx_vcs.is_p4_managed(filepath) then
            return 
        end

        -- ユーザーに確認ダイアログを出す
        local choice = vim.fn.confirm(
            "File is Read-Only (Perforce Managed).\nCheckout to edit?", 
            "&Yes\n&No", 
            1
        )
        
        if choice == 1 then
            -- P4 Edit を実行
            local success = unx_vcs.p4_edit(filepath)
            
            if success then
                -- 成功したらバッファの「読み取り専用」フラグを強制解除する
                vim.bo[buf].readonly = false
                vim.bo[buf].modifiable = true
                
                -- 外部で属性が変わったことをVimに認識させる
                vim.cmd("checktime") 
                
                vim.notify("Checkout successful. File is now writable.", vim.log.levels.INFO)
            else
                vim.notify("Checkout failed.", vim.log.levels.ERROR)
            end
        end
    end

    -- 1. 編集しようとした瞬間 (W10警告が出るタイミング) にフック
    vim.api.nvim_create_autocmd("FileChangedRO", {
        group = group,
        pattern = "*",
        callback = function(args)
            local buf = args.buf
            local filepath = vim.api.nvim_buf_get_name(buf)
            -- 既に書き込み可能なら無視
            if not vim.bo[buf].readonly then return end
            
            -- ロジック実行
            try_checkout(buf, filepath)
        end
    })

    -- 2. 保存しようとした瞬間 (E45エラーが出るタイミング) にフック
    vim.api.nvim_create_autocmd("BufWritePre", {
        group = group,
        pattern = "*",
        callback = function(args)
            local buf = args.buf
            local filepath = vim.api.nvim_buf_get_name(buf)
            
            -- ReadOnlyの場合のみ発動
            if vim.bo[buf].readonly then
                try_checkout(buf, filepath)
            end
        end
    })
end

return M

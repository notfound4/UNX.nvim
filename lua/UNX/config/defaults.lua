local M = {}

M.defaults = {
    -- ウィンドウ設定
    window = {
        position = "left",
        size = {
            width = 35,
        },
    },
    -- ログ設定
    cache = { dirname = "UNX" },
    logging = {
        level = "info",
        echo = { level = "warn" },
        notify = { level = "error", prefix = "[UNX]" },
        file = { level = "debug", enable = true, max_kb = 512, rotate = 3, filename = "unx.log" },
        perf = { enabled = false, patterns = { "^refresh" }, level = "trace" },
    },
    -- ハイライト設定 (標準グループへのリンク)
    -- ユーザーは setup() でこれらを上書き可能
    highlights = {
        -- 基本UI
        UNXDirectoryIcon = { link = "Directory" }, -- ディレクトリ色 (通常は青系)
        UNXFileIcon      = { link = "Comment" },   -- ファイルアイコン (控えめな色)
        UNXFileName      = { link = "Normal" },    -- ファイル名 (通常色)
        UNXIndentMarker  = { link = "NonText" },   -- インデントガイド (目立たない色)
        UNXModifiedIcon  = { link = "Special" },   -- 変更ありアイコン (目立つ色)
        
        -- Git Status
        UNXGitModified   = { link = "Special" },    -- 変更 (黄色/紫など)
        UNXGitAdded      = { link = "String" },     -- 追加 (緑系が多い)
        UNXGitDeleted    = { link = "Error" },      -- 削除 (赤系)
        UNXGitRenamed    = { link = "Title" },      -- 移動/名前変更 (目立つ色)
        UNXGitConflict   = { link = "ErrorMsg" },   -- 競合 (警告色)
        UNXGitUntracked  = { link = "Function" },   -- 未追跡 (青/水色系が多い)
        UNXGitIgnored    = { link = "Comment" },    -- 無視 (グレー)
    },
    uproject = {
        show_hidden = false,
        icon = {
            expander_open   = "",
            expander_closed = "",
            folder_closed   = "",
            folder_open     = "",
            default_file    = "",
            modified        = "[+] ",
        },
        git_icons = {
            Modified  = "",
            Added     = "✚",
            Deleted   = "✖",
            Renamed   = "➜",
            Conflict  = "",
            Untracked = "★",
            Ignored   = "◌",
        },
    },
    keymaps = {
        close = { "q" },
        open = { "<CR>", "o" },
        vsplit = "s",
        split = "i",
    },
}

return M.defaults

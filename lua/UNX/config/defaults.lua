local M = {}

M.defaults = {
    -- ウィンドウ設定
    window = {
        position = "left",
        size = {
            width = 35,
        },
    },
    cache = { dirname = "UNX" },
    logging = {
        level = "info",
        echo = { level = "warn" },
        notify = { level = "error", prefix = "[UNX]" },
        file = { level = "debug", enable = true, max_kb = 512, rotate = 3, filename = "unx.log" },
        perf = { enabled = false, patterns = { "^refresh" }, level = "trace" },
    },
    highlights = {
        UNXDirectoryIcon = { link = "Directory" },
        UNXFileIcon      = { link = "Comment" },
        UNXFileName      = { link = "Normal" },
        UNXIndentMarker  = { link = "NonText" },
        UNXModifiedIcon  = { link = "Special" },
        
        UNXGitModified   = { link = "Special" },
        UNXGitAdded      = { link = "String" },
        UNXGitDeleted    = { link = "Error" },
        UNXGitRenamed    = { link = "Title" },
        UNXGitConflict   = { link = "ErrorMsg" },
        UNXGitUntracked  = { link = "Function" },
        UNXGitIgnored    = { link = "Comment" },
    },
    uproject = {
        show_hidden = false,
        icon = {
            expander_open   = "",
            expander_closed = "",
            folder_closed   = "",
            folder_open     = "",
            default_file    = "",
            modified        = "[+] ", -- デフォルトのテキスト（コンポーネントで使用）
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
        -- ★追加: UIコンポーネント設定
        ui = {
            -- 右側に表示するコンポーネントの順序 (左 -> 右)
            right_components = {
                "git_status",
                "modified_buffer",
            },
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

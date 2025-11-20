local M = {}

M.defaults = {
    -- ウィンドウ設定
    window = {
        position = "left",
        size = {
            width = 35,
        },
    },
    -- ★追加: ログ設定 (UNLの仕様に合わせる)
    logging = {
        level = "info",
        file = { enable = true, filename = "unx.log" },
        notify = { level = "warn", prefix = "[UNX]" },
    },
    -- ハイライト設定
    highlights = {
        UNXDirectoryIcon = { fg = "#73CEF4" },
        UNXFileIcon      = { fg = "#888888" },
        UNXFileName      = { fg = "NONE" },
        UNXIndentMarker  = { fg = "#626262" },
        UNXModifiedIcon  = { fg = "#D7D787" },
        
        UNXGitModified   = { fg = "#D7D787" },
        UNXGitAdded      = { fg = "#5FAF5F" },
        UNXGitDeleted    = { fg = "#FF5900" },
        UNXGitRenamed    = { fg = "#D7D787" },
        UNXGitConflict   = { fg = "#FF8700", bold = true },
        UNXGitUntracked  = { fg = "#5FAF5F", italic = true },
        UNXGitIgnored    = { fg = "#626262" },
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

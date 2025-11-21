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
        ui = {
            right_components = {
                "git_status",
                "modified_buffer",
            },
        },
    },
    -- ★追加: Safe Open 設定
    safe_open = {
        -- 開くのを避けるバッファタイプ
        prevent_in_buftypes = {
            "quickfix",
            "help",
            "terminal",
            "prompt",
        },
        -- 開くのを避けるファイルタイプ
        prevent_in_filetypes = {
            "neo-tree",
            "NvimTree",
            "TelescopePrompt",
            "fugitive",
            "lazy",
            "unx-explorer", -- UNX自身のバッファでも開かないようにする
        },
    },
    keymaps = {
        close = { "q" },
        open = { "<CR>", "o" },
        vsplit = "s",
        split = "i",
        
        action_add = "a",
        action_delete = "d",
        action_move = "m",
        action_rename = "r",
    },
}

return M.defaults

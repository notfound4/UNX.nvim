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
        level = "trace",
        echo = { level = "warn" },
        notify = { level = "error", prefix = "[UNX]" },
        file = { level = "trace", enable = true, max_kb = 512, rotate = 3, filename = "unx.log" },
        perf = { enabled = false, patterns = { "^refresh" }, level = "trace" },
    },
highlights = {
        UNXDirectoryIcon = { link = "Directory" },
        UNXFileIcon      = { link = "Comment" },
        UNXFileName      = { link = "Normal" },
        UNXIndentMarker  = { link = "NonText" },
        UNXModifiedIcon  = { link = "Special" },

        UNXTabActive     = { link = "UNXVCSAdded" },   -- ★ 修正
        UNXTabInactive   = { link = "Normal" },
        UNXTabSeparator  = { link = "NonText" },

        -- ★★★ 完全リネーム & 新規追加 ★★★
        UNXVCSModified   = { link = "Special" },
        UNXVCSAdded      = { link = "String" },
        UNXVCSDeleted    = { link = "Error" },
        UNXVCSRenamed    = { link = "Title" },
        UNXVCSConflict   = { link = "ErrorMsg" },
        UNXVCSUntracked  = { link = "Function" },
        UNXVCSIgnored    = { link = "Comment" },
        
        -- ★ 新規作成: これでシンボルやWinbarが綺麗になります
        UNXVCSFunction   = { link = "Function" }, 
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
        vcs_icons = {
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
                "vcs_status",
                "modified_buffer",
            },
        },
    },
    -- Safe Open 設定
    safe_open = {
        prevent_in_buftypes = {
            "nofile",
            "quickfix",
            "help",
            "terminal",
            "prompt",
        },
        prevent_in_filetypes = {
            "neo-tree",
            "NvimTree",
            "TelescopePrompt",
            "fugitive",
            "lazy",
            "unx-explorer",
        },
    },
   insights_ui = { -- ★★★ 新規追加 ★★★
        icon = {
            -- ノードが子を持つ場合のアイコン（=フォルダ/グループ）
            group_icon_open = "",      -- ★★★ 開いているフォルダアイコン ★★★
            group_icon_closed = "",    -- ★★★ 閉じているフォルダアイコン ★★★
            group_icon_hl = "UNXDirectoryIcon",
            -- ノードが子を持たない場合のアイコン（=関数/イベント）
            leaf_icon = "󰊕", 
            leaf_icon_hl = "Function",
        },
    },


  vcs = {
    git = {
        enabled = true,
    },
    p4 = {
        enabled = true,
        auto_checkout = true,
    },
  },
    keymaps = {
        close = { "q" },
        open = { "<CR>", "o" },
        vsplit = "s",
        split = "i",
        
        action_add = "a",
        action_add_directory = "A", -- ★追加
        action_delete = "d",
        action_move = "m",
        action_rename = "r",
    },
}

return M.defaults

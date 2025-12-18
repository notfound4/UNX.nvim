if vim.g.loaded_unx == 1 then
  return
end
vim.g.loaded_unx = 1

local builder = require("UNL.command.builder")

-- サブコマンドの定義
local subcommands = {
    open = {
        desc = "Open the explorer window",
        handler = function(args)
            -- ★変更: API経由で呼び出し
            require("UNX.api").explorer_open()
        end,
    },
    refresh = {
        desc = "Refresh the explorer tree",
        handler = function(args)
            -- ★変更: API経由で呼び出し
            require("UNX.api").explorer_refresh()
        end,
    },
    close = {
        desc = "Close the explorer window",
        handler = function(args)
            -- ★変更: API経由で呼び出し
            require("UNX.api").explorer_close()
        end,
    },
    -- ★追加: APIにある toggle もコマンドとして使えるように追加
    toggle = {
        desc = "Toggle the explorer window",
        handler = function(args)
            require("UNX.api").explorer_toggle()
        end,
    },

    ["add_favorites"] = {
      handler = require("UNX.api").add_favorites,
      desc = "Add files/directories to Favorites via picker.",
      args = {
        { name = "scope", required = false },
        { name = "deps_flag", required = false },
      },
    },
    ["favorites_files"] = {
        handler = require("UNX.api").favorites_files,
        desc = "List and open files from Favorites.",
        args = {},
    },
    ["pending_files"] = {
        handler = require("UNX.api").pending_files,
        desc = "List pending (local) changes.",
        args = {},
    },
    ["unpushed_files"] = {
        handler = require("UNX.api").unpushed_files,
        desc = "List unpushed (remote) files.",
        args = {},
    },
    ["favorite_current"] = {
        handler = require("UNX.api").favorite_current,
        desc = "Toggle the current buffer in Favorites.",
        args = {},
    },
}

-- コマンドの登録
builder.create({
    cmd_name = "UNX",
    name = "UNX",
    desc = "Unreal Neovim eXplorer",
    subcommands = subcommands,
})

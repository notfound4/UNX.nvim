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
    }
}

-- コマンドの登録
builder.create({
    cmd_name = "UNX",
    name = "UNX",
    desc = "Unreal Neovim eXplorer",
    subcommands = subcommands,
})

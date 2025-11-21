if vim.g.loaded_unx == 1 then
  return
end
vim.g.loaded_unx = 1

local builder = require("UNL.command.builder")

-- サブコマンドの定義
local subcommands = {
    open = {
        desc = "Open the explorer window",
        handler = function(args) -- 修正: impl -> handler
            require("UNX.ui.explorer").open()
        end,
    },
    refresh = {
        desc = "Refresh the explorer tree",
        handler = function(args) -- 修正: impl -> handler
            require("UNX.ui.explorer").refresh()
        end,
    },
    close = {
        desc = "Close the explorer window",
        handler = function(args) -- 修正: impl -> handler
          require("UNX.ui.explorer").close()
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

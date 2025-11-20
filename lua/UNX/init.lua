local M = {}
M.config = {}

-- ★追加: UNLのロギングモジュールをロード
local unl_log = require("UNL.logging")

local function setup_highlights(highlights)
    for group, opts in pairs(highlights) do
        opts.default = true
        vim.api.nvim_set_hl(0, group, opts)
    end
end

function M.setup(user_config)
    local default_config = require("UNX.config.defaults")
    M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

    -- ★追加: "UNX" という名前でロガーを初期化
    -- これで provider.request 時の logger_name = "UNX" が正しく機能します
    unl_log.setup("UNX", default_config, user_config)

    setup_highlights(M.config.highlights)
    
    require("UNX.ui.explorer").setup(M.config)
end

return M

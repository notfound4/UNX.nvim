-- lua/UNX/provider/init.lua (新規作成)

local M = {}

M.setup = function()
    local unl_api_ok, unl_api = pcall(require, "UNL.api")
    if unl_api_ok then
        local provider_core = require("UNX.provider.core") -- ★ core.lua にリネーム
        
        -- open プロバイダーの登録
        unl_api.provider.register({
          capability = "unx.open",
          name = "UNX.nvim",
          impl = provider_core, -- impl は core.lua のモジュール全体
        })
        
        -- is_open プロバイダーの登録
        unl_api.provider.register({
          capability = "unx.is_open",
          name = "UNX.nvim",
          impl = provider_core,
        })
        
        require("UNX.logger").get().info("Registered UNX providers to UNL.nvim.")
    end
end

return M

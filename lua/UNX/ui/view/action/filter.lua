local ctx_uproject = require("UNX.context.uproject")
local logger = require("UNX.logger")

local M = {}

-- フィルタリング開始（入力プロンプト表示）
function M.start_filter(tree)
    local ctx = ctx_uproject.get()
    local current_filter = ctx.filter_text or ""
    
    vim.ui.input({ 
        prompt = "Filter Tree (/ to clear): ", 
        default = current_filter 
    }, function(input)
        if input == nil then return end -- Cancelled
        
        -- "/" だけ入力されたらクリアとみなす
        if input == "/" then input = "" end
        
        ctx.filter_text = input
        ctx_uproject.set(ctx)
        
        -- ツリーリフレッシュ（ここでフィルタリングが適用される）
        require("UNX.ui.view.uproject").refresh(tree)
        
        if input ~= "" then
            logger.get().info("Filter applied: " .. input)
        else
            logger.get().info("Filter cleared.")
        end
    end)
end

function M.clear_filter(tree)
    local ctx = ctx_uproject.get()
    if ctx.filter_text == "" then return end
    
    ctx.filter_text = ""
    ctx_uproject.set(ctx)
    require("UNX.ui.view.uproject").refresh(tree)
    logger.get().info("Filter cleared.")
end

return M

local unx_git = require("UNX.git")
local utils = require("UNX.common.utils")

-- node: ツリーノード
-- context: 描画コンテキスト (必要なら使用)
-- config: ユーザー設定
return function(node, context, config)
    if not node.path then return nil end
    
    local path = utils.normalize_path(node.path)
    local status = unx_git.get_status(path)
    
    if status then
        local icon, hl = utils.get_git_icon_and_hl(status, config)
        return { text = icon, highlight = hl }
    end
    
    return nil
end

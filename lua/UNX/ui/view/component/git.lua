local unx_git = require("UNX.git")
local utils = require("UNX.common.utils")
-- ★追加: UNL.path を使用
local unl_path = require("UNL.path")

-- node: ツリーノード
-- context: 描画コンテキスト (必要なら使用)
-- config: ユーザー設定
return function(node, context, config)
    if not node.path then return nil end
    
    -- ★修正: utils.normalize_path (廃止) -> unl_path.normalize
    -- Gitステータスの検索キー生成は unx_git 内部でさらに正規化・小文字化されるため
    -- ここでは標準の正規化を通すだけでOKです。
    local path = unl_path.normalize(node.path)
    
    local status = unx_git.get_status(path)
    
    if status then
        local icon, hl = utils.get_git_icon_and_hl(status, config)
        return { text = icon, highlight = hl }
    end
    
    return nil
end

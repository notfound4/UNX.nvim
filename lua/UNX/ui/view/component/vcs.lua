-- lua/UNX/ui/view/component/vcs.lua
local unx_vcs = require("UNX.vcs")
local utils = require("UNX.common.utils")
local unl_path = require("UNL.path")

return function(node, context, config)
    if not node.path then return nil end
    
    local path = unl_path.normalize(node.path)
    local status = unx_vcs.get_status(path)
    
    if status then
        local icon, hl = utils.get_vcs_icon_and_hl(status, config)
        return { text = icon, highlight = hl }
    end
    
    return nil
end

local utils = require("UNX.common.utils")

return function(node, context, config)
    if not node.path then return nil end
    
    local path = utils.normalize_path(node.path)
    local opened = utils.get_opened_buffers_status()
    
    if path and opened[path] and opened[path].modified then
        local icon = config.uproject.icon.modified or "[+] "
        return { text = icon, highlight = "UNXModifiedIcon" }
    end
    
    return nil
end

local M = {}
local unx_vcs = require("UNX.vcs")
local unl_open = require("UNL.buf.open")
local logger = require("UNX.logger")

function M.diff(tree)
    local node = tree:get_node()
    if not node then return end
    
    local path = node.path
    if not path or node.type ~= "file" then 
        logger.get().warn("Please select a file to diff.")
        return 
    end
    
    local filename = vim.fn.fnamemodify(path, ":t")
    
    unx_vcs.get_file_content(path, function(content)
        if not content then
            -- If content is nil, assume it's a new file (untracked or added) or retrieval failed.
            -- Treat as empty base content to allow diffing (showing all lines as added).
            content = ""
        end
        
        vim.schedule(function()
            -- 1. Open the local file (this handles finding the right window)
            unl_open.safe({
                file_path = path,
                open_cmd = "edit",
                plugin_name = "UNX",
            })
            
            -- Ensure we are in the window with the file
            local current_buf = vim.api.nvim_get_current_buf()
            local current_path = vim.api.nvim_buf_get_name(current_buf)
            
            -- Normalizing paths for comparison might be safer
            -- but unl_open.safe should have focused the buffer.
            
            vim.cmd("diffthis")
            
            -- 2. Open the base content in a vertical split
            vim.cmd("leftabove vnew") -- Open on the left (Base)
            local buf = vim.api.nvim_get_current_buf()
            
            -- Set content
            -- Handle potential CR/LF issues if needed, but split handles string
            local lines = vim.split(content, "\n")
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            
            -- Set buffer options
            vim.bo[buf].buftype = "nofile"
            vim.bo[buf].bufhidden = "wipe"
            vim.bo[buf].swapfile = false
            vim.bo[buf].modifiable = false
            
            -- Try to detect filetype
            local ft = vim.filetype.match({ filename = path })
            if ft then vim.bo[buf].filetype = ft end
            
            vim.api.nvim_buf_set_name(buf, "Base: " .. filename)
            
            vim.cmd("diffthis")
            
            -- Return focus to the local file (on the right)
            vim.cmd("wincmd p")
        end)
    end)
end

return M

local M = {}

-- パス正規化 (Windows対応: セパレータ統一 & 小文字化)
local is_windows = vim.fn.has("win32") == 1 or vim.fn.has("wsl") == 1
function M.normalize_path(path)
  if not path then return nil end
  local p = path:gsub("\\", "/")
  if is_windows then
    p = p:lower()
  end
  return p
end

-- 開いているバッファの変更状態を取得
function M.get_opened_buffers_status()
    local opened_buffers = {}
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.fn.buflisted(buffer) ~= 0 then
            local name = vim.api.nvim_buf_get_name(buffer)
            if name == "" then name = "[No Name]#" .. buffer end
            local norm_name = M.normalize_path(name)
            if norm_name then
                opened_buffers[norm_name] = { modified = vim.bo[buffer].modified }
            end
        end
    end
    return opened_buffers
end

-- Gitステータスのアイコンとハイライトを取得
function M.get_git_icon_and_hl(status_code, config)
    local icons = config.uproject and config.uproject.git_icons or {}
    if status_code == "M" then return icons.Modified or "M", "UNXGitModified" end
    if status_code == "A" then return icons.Added or "A", "UNXGitAdded" end
    if status_code == "D" then return icons.Deleted or "D", "UNXGitDeleted" end
    if status_code == "R" then return icons.Renamed or "R", "UNXGitRenamed" end
    if status_code == "C" then return icons.Conflict or "C", "UNXGitConflict" end
    if status_code == "??" then return icons.Untracked or "?", "UNXGitUntracked" end
    if status_code == "!!" then return icons.Ignored or "!", "UNXGitIgnored" end
    return "", "UNXFileName"
end

return M

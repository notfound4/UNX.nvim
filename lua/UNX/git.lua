-- lua/UNX/git.lua
local M = {}
local status_cache = {}
local is_running = false

-- Gitステータスを非同期で更新
function M.refresh(root_path, on_complete)
    if is_running or not root_path then return end
    
    -- .git ディレクトリがあるか簡易チェック (なくても gitコマンドは動くが、無駄な呼び出しを減らす)
    -- ただし親ディレクトリがrepoの場合もあるので、厳密には git rev-parse が正しいが、
    -- ここではエラーハンドリングでカバーする
    
    is_running = true
    local cmd = { "git", "-C", root_path, "status", "--porcelain", "-uall" }
    local stdout = {}

    vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then table.insert(stdout, line) end
                end
            end
        end,
        on_exit = function(_, code)
            is_running = false
            if code == 0 then
                -- 成功時のみキャッシュ更新
                local new_cache = {}
                for _, line in ipairs(stdout) do
                    if #line > 3 then
                        local status_code = line:sub(1, 2)
                        local rel_path = line:sub(4):gsub('^"(.*)"$', "%1")
                        -- root_path からの相対パスを絶対パスに変換してキーにする
                        local abs_path = root_path .. "/" .. rel_path
                        abs_path = abs_path:gsub("\\", "/")
                        
                        local s = nil
                        if status_code:match("M") then s = "M"
                        elseif status_code:match("A") then s = "A"
                        elseif status_code:match("D") then s = "D"
                        elseif status_code:match("R") then s = "R"
                        elseif status_code:match("C") then s = "C"
                        elseif status_code:match("%?") then s = "??"
                        elseif status_code:match("!") then s = "!!"
                        end
                        
                        if s then new_cache[abs_path] = s end
                    end
                end
                status_cache = new_cache
            else
                -- Gitリポジトリじゃない場合などはキャッシュをクリア
                status_cache = {}
            end
            
            if on_complete then vim.schedule(on_complete) end
        end
    })
end

-- 指定パスのステータスを取得
function M.get_status(path)
    if not path then return nil end
    path = path:gsub("\\", "/")
    return status_cache[path]
end

return M

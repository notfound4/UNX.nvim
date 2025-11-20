-- lua/UNX/git.lua
local M = {}
local status_cache = {}
local is_running = false

-- Gitステータスを非同期で更新
function M.refresh(root_path, on_complete)
    if is_running or not root_path then return end
    
    -- ルートパスの正規化（末尾スラッシュ削除）
    root_path = root_path:gsub("\\", "/"):gsub("/$", "")
    
    is_running = true
    
    -- core.quotepath=false を指定して日本語ファイル名などのエスケープを防ぐ
    -- Windowsパス問題を防ぐため、相対パスで取得し、Lua側で絶対パス化する
    local cmd = { "git", "-C", root_path, "-c", "core.quotepath=false", "status", "--porcelain", "-uall" }
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
                local new_cache = {}
                for _, line in ipairs(stdout) do
                    if #line > 3 then
                        local status_code = line:sub(1, 2)
                        -- ステータスコード以降のファイルパスを取得
                        local rel_path = line:sub(4)
                        -- 引用符があれば除去
                        rel_path = rel_path:gsub('^"(.*)"$', "%1")
                        
                        -- 絶対パス化してキーにする (Windowsセパレータ対応)
                        local abs_path = root_path .. "/" .. rel_path
                        abs_path = abs_path:gsub("\\", "/")
                        
                        local s = nil
                        -- ステータス判定ロジック
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
                -- 失敗時キャッシュクリア
                status_cache = {}
            end
            
            -- 完了コールバック
            if on_complete then vim.schedule(on_complete) end
        end
    })
end

-- 指定パスのステータスを取得
function M.get_status(path)
    if not path then return nil end
    -- 検索キーも正規化
    path = path:gsub("\\", "/")
    return status_cache[path]
end

return M

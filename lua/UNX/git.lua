-- lua/UNX/git.lua
-- ★変更: UNX.common.utils ではなく UNL.path を使用
local unl_path = require("UNL.path")
local M = {}

-- キャッシュ: [正規化されたパス] = "ステータスコード"
local git_status_cache = {}

-- Windows判定 (キャッシュキー生成用)
local is_windows = vim.fn.has("win32") == 1 or vim.fn.has("wsl") == 1

--- キャッシュ用のキーを生成するヘルパー
-- UNL.path.normalize を使いつつ、Windowsの場合は小文字化してキーの一致を保証する
local function make_key(path)
    local p = unl_path.normalize(path)
    if p and is_windows then
        return p:lower()
    end
    return p
end

--- Gitステータスを解析する内部関数
local function parse_git_status(root_path, output_str)
    local new_cache = {}
    
    for line in output_str:gmatch("[^\r\n]+") do
        if #line > 3 then
            -- 1-2文字目がステータス
            local status = line:sub(1, 2):gsub("%s", "")
            
            -- 4文字目以降がファイルパス
            local rel_path = line:sub(4)
            
            -- クォート除去
            if rel_path:sub(1, 1) == '"' then
                rel_path = rel_path:sub(2, -2)
            end

            -- 絶対パスを作成 (UNL.path.join を使っても良いですが、単純結合で十分です)
            local abs_path = root_path .. "/" .. rel_path
            
            -- ★重要: make_key (UNL.path利用) でキーを作成
            local key = make_key(abs_path)
            
            if key then
                new_cache[key] = status
            end
        end
    end
    
    return new_cache
end

--- 指定したルートディレクトリで git status を更新する (非同期)
function M.refresh(root_path, on_complete)
    if not root_path then return end

    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)
    local output_data = ""

    local handle, pid
    handle, pid = vim.loop.spawn("git", {
        args = { "status", "--porcelain", "-u", "--no-renames" },
        cwd = root_path,
        stdio = { nil, stdout, stderr }
    }, function(code, signal)
        stdout:read_stop()
        stderr:read_stop()
        stdout:close()
        stderr:close()
        handle:close()

        if code == 0 then
            vim.schedule(function()
                git_status_cache = parse_git_status(root_path, output_data)
                if on_complete then
                    on_complete()
                end
            end)
        end
    end)

    if handle then
        vim.loop.read_start(stdout, function(err, data)
            assert(not err, err)
            if data then output_data = output_data .. data end
        end)
        vim.loop.read_start(stderr, function(err, data) end)
    end
end

--- パスのGitステータスを取得する
function M.get_status(path)
    if not path then return nil end
    -- ★重要: 検索時も make_key を通す
    return git_status_cache[make_key(path)]
end

--- キャッシュをクリアする
function M.clear()
    git_status_cache = {}
end

return M

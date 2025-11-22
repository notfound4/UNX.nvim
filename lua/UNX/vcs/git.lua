-- lua/UNX/git.lua
local unl_path = require("UNL.path")
local logger = require("UNX.logger")
local M = {}

-- キャッシュ: [正規化されたパス] = "ステータスコード"
local git_status_cache = {}

-- ★変更: Windows判定は残すが、強制小文字化には使わない
-- local is_windows = vim.fn.has("win32") == 1 or vim.fn.has("wsl") == 1

-- キャッシュキー生成ヘルパー
local function make_key(path)
    -- ★変更: UNL.path.normalize のみを行う (小文字化はしない)
    -- これにより "Foo.cpp" と "foo.cpp" は別のキーとして扱われる
    return unl_path.normalize(path)
end

-- Gitコマンド実行ヘルパー (非同期)
local function spawn_git(args, cwd, on_success)
    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)
    local output_data = ""

    -- logger.get().debug(string.format("Spawning git %s in %s", table.concat(args, " "), cwd))

    local handle, pid
    handle, pid = vim.loop.spawn("git", {
        args = args,
        cwd = cwd,
        stdio = { nil, stdout, stderr }
    }, function(code, signal)
        stdout:read_stop()
        stderr:read_stop()
        stdout:close()
        stderr:close()
        handle:close()

        vim.schedule(function()
            if code == 0 then
                on_success(output_data)
            else
                -- 警告ログ
                logger.get().warn(string.format("Git command failed: %s (code: %d)", table.concat(args, " "), code))
                on_success("") 
            end
        end)
    end)

    if handle then
        vim.loop.read_start(stdout, function(err, data)
            if data then output_data = output_data .. data end
        end)
        vim.loop.read_start(stderr, function(err, data) end)
    else
        logger.get().error("Failed to spawn git process")
        vim.schedule(function() on_success("") end)
    end
end

-- git status 出力をパースしてキャッシュに追加
local function parse_status_output(base_path, output_str, cache_table)
    if not output_str or output_str == "" then return end

    for line in output_str:gmatch("[^\r\n]+") do
        if #line > 3 then
            local status = line:sub(1, 2):gsub("%s", "")
            local rel_path = line:sub(4)
            
            if rel_path:sub(1, 1) == '"' then
                rel_path = rel_path:sub(2, -2)
            end
            
            -- base_path と結合して絶対パスにする
            local abs_path = base_path .. "/" .. rel_path
            local key = make_key(abs_path)
            
            if key then
                -- デバッグログ: キャッシュ登録
                -- logger.get().trace(string.format("Git Cache Add: [%s] -> %s", key, status))
                cache_table[key] = status
            end
        end
    end
end

--- プロジェクト全体のGitステータスを更新
function M.refresh(start_path, on_complete)
    if not start_path then return end
    
    -- logger.get().debug("Git Refresh requested for: " .. start_path)

    -- 1. Git Root を探す
    spawn_git({"rev-parse", "--show-toplevel"}, start_path, function(output)
        local git_root = output and output:gsub("[\r\n]+", "") or ""
        
        if git_root == "" then
            logger.get().debug("Not a git repository (rev-parse failed) at " .. start_path)
            if on_complete then on_complete() end
            return
        end

        git_root = unl_path.normalize(git_root)
        -- logger.get().debug("Detected Git Root: " .. git_root)

        local pending_jobs = 1 
        local new_cache = {}
        local is_finished = false

        local function check_done()
            pending_jobs = pending_jobs - 1
            if pending_jobs <= 0 and not is_finished then
                is_finished = true
                git_status_cache = new_cache
                
                logger.get().debug(string.format("Git Refresh complete. Items in cache: %d", vim.tbl_count(git_status_cache)))
                if on_complete then on_complete() end
            end
        end

        -- 2. サブモジュール一覧取得
        spawn_git({"submodule", "status", "--recursive"}, git_root, function(sub_out)
            
            -- 3. ルート自身のステータス取得
            pending_jobs = pending_jobs + 1
            spawn_git({"status", "--porcelain", "-u", "--no-renames"}, git_root, function(root_stat)
                parse_status_output(git_root, root_stat, new_cache)
                check_done()
            end)

            -- 4. 各サブモジュールのステータス取得
            if sub_out and sub_out ~= "" then
                for line in sub_out:gmatch("[^\r\n]+") do
                    local clean_line = line:match("^%W*(.+)$")
                    if clean_line then
                        local parts = {}
                        for p in clean_line:gmatch("%S+") do table.insert(parts, p) end
                        
                        if #parts >= 2 then
                            local sub_rel_path = parts[2]
                            local sub_abs_path = git_root .. "/" .. sub_rel_path
                            sub_abs_path = unl_path.normalize(sub_abs_path)
                            
                            -- logger.get().debug("Processing submodule: " .. sub_abs_path)

                            pending_jobs = pending_jobs + 1
                            spawn_git({"status", "--porcelain", "-u", "--no-renames"}, sub_abs_path, function(sub_stat)
                                parse_status_output(sub_abs_path, sub_stat, new_cache)
                                check_done()
                            end)
                        end
                    end
                end
            end

            check_done()
        end)
    end)
end

function M.get_status(path)
    if not path then return nil end
    local key = make_key(path)
    local stat = git_status_cache[key]
    
    -- デバッグ用: キャッシュミス時にログを出す場合
    -- if not stat then
    --    logger.get().trace("get_status MISS: " .. key)
    -- end
    
    return stat
end

function M.clear()
    git_status_cache = {}
end

return M

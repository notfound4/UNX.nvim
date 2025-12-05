local unl_path = require("UNL.path")
local logger = require("UNX.logger")
local M = {}

local git_status_cache = {}

-- キャッシュキー生成
local function make_key(path)
    return unl_path.normalize(path)
end

-- Gitコマンド実行ヘルパー (エラーログはそのまま残しておいてOK)
local function spawn_git(args, cwd, on_success)
    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)
    local output_data = ""

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
                -- 実行前に .git チェックをするので、ここで失敗するのは本当に異常な場合のみ
                logger.get().warn(string.format("Git command failed: %s (code: %d)", table.concat(args, " "), code))
                on_success(nil) 
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
        vim.schedule(function() on_success(nil) end)
    end
end

local function parse_status_output(base_path, output_str, cache_table)
    if not output_str or output_str == "" then return end

    for line in output_str:gmatch("[^\r\n]+") do
        if #line > 3 then
            local status = line:sub(1, 2):gsub("%s", "")
            local rel_path = line:sub(4)
            if rel_path:sub(1, 1) == '"' then rel_path = rel_path:sub(2, -2) end
            local abs_path = base_path .. "/" .. rel_path
            local key = make_key(abs_path)
            if key then cache_table[key] = status end
        end
    end
end

function M.refresh(start_path, on_complete)
    if not start_path then return end

    -- ★★★ 修正: 先に .git があるかチェック (上方検索) ★★★
    -- vim.fs.find は Neovim 0.10+ で推奨。なければ vim.fn.finddir 等でも可
    local found = vim.fs.find(".git", { path = start_path, upward = true, type = "directory" })
    
    -- submodule (ファイルとしての.git) も考慮する場合
    if #found == 0 then
        found = vim.fs.find(".git", { path = start_path, upward = true, type = "file" })
    end

    if #found == 0 then
        -- .git が見つからない = Gitリポジトリではない
        -- 何もせず、エラーも出さずに終了
        if on_complete then on_complete() end
        return
    end
    -- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★

    -- ここまで来たら Git リポジトリ内なので、堂々とコマンドを実行
    spawn_git({"rev-parse", "--show-toplevel"}, start_path, function(output)
        local git_root = output and output:gsub("[\r\n]+", "") or ""
        
        if git_root == "" then
            if on_complete then on_complete() end
            return
        end

        git_root = unl_path.normalize(git_root)
        local pending_jobs = 1 
        local new_cache = {}
        local is_finished = false

        local function check_done()
            pending_jobs = pending_jobs - 1
            if pending_jobs <= 0 and not is_finished then
                is_finished = true
                git_status_cache = new_cache
                -- logger.get().debug("Git Refresh complete.")
                if on_complete then on_complete() end
            end
        end

        spawn_git({"submodule", "status", "--recursive"}, git_root, function(sub_out)
            pending_jobs = pending_jobs + 1
            spawn_git({"status", "--porcelain", "-u", "--no-renames"}, git_root, function(root_stat)
                parse_status_output(git_root, root_stat, new_cache)
                check_done()
            end)

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
    return git_status_cache[key]
end

function M.clear()
    git_status_cache = {}
end

function M.get_changes()
    local changes = {}
    for path, status in pairs(git_status_cache) do
        -- Ignored (!!) は除外、それ以外は含める
        if status ~= "!!" then
            table.insert(changes, { path = path, status = status })
        end
    end
    return changes
end

return M

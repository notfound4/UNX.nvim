-- lua/UNX/vcs/p4.lua
local unl_path = require("UNL.path")
local logger = require("UNX.logger")
local M = {}

-- キャッシュ: [正規化されたパス] = "ステータスコード" (例: "edit", "add", "delete")
local p4_status_cache = {}
local is_available = nil -- P4が使えるかどうかのフラグ

-- キャッシュキー生成
local function make_key(path)
    return unl_path.normalize(path)
end

-- 非同期 P4 コマンド実行 (spawn)
local function spawn_p4(args, cwd, on_success)
    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)
    local output_data = ""

    local handle, pid
    handle, pid = vim.loop.spawn("p4", {
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
                -- 接続エラーなどの場合はログを出して空を返す
                -- logger.get().trace("P4 command failed or not connected: " .. table.concat(args, " "))
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
        on_success(nil)
    end
end

-- P4が利用可能かチェック (初回のみ)
local function check_availability(cwd, callback)
    if is_available ~= nil then
        callback(is_available)
        return
    end
    -- "p4 info" は遅いことがあるので、軽量な "p4 client -o" や単にコマンド存在確認でも良いが
    -- 確実にワークスペース内か判定するため "p4 where" をカレントディレクトリで試すのが手堅い
    spawn_p4({ "where", "." }, cwd, function(output)
        is_available = (output ~= nil and output ~= "")
        callback(is_available)
    end)
end

--- プロジェクト全体のステータス更新
--- 戦略: "p4 opened" で自分がチェックアウトしているファイル一覧だけを取得する (高速)
--- 他人がチェックアウトしているファイルを知りたい場合は "p4 opened -a" だが遅くなるため、まずは自分のファイルのみ。
function M.refresh(start_path, on_complete)
    if not start_path then return end
    
    check_availability(start_path, function(available)
        if not available then
            if on_complete then on_complete() end
            return
        end

        -- -F でフォーマット指定: クライアントパス|アクション
        -- "..." は再帰的に全ファイル対象
        local args = { "-F", "%clientFile%|%action%", "opened", "..." }
        
        spawn_p4(args, start_path, function(output)
            local new_cache = {}
            if output then
                for line in output:gmatch("[^\r\n]+") do
                    -- 例: c:\Work\MyProject\Source\File.cpp|edit
                    local path_part, action = line:match("^(.*)|(.*)$")
                    if path_part and action then
                        local key = make_key(path_part)
                        
                        -- UNXの汎用ステータスコードに変換
                        local status_code = "M" -- Default Modified
                        if action == "add" then status_code = "A"
                        elseif action == "delete" then status_code = "D"
                        elseif action == "move/add" then status_code = "R"
                        elseif action == "edit" then status_code = "M" 
                        end
                        
                        new_cache[key] = status_code
                    end
                end
            end
            
            p4_status_cache = new_cache
            logger.get().debug(string.format("P4 Refresh complete. Opened files: %d", vim.tbl_count(p4_status_cache)))
            if on_complete then on_complete() end
        end)
    end)
end

function M.get_status(path)
    if not path then return nil end
    return p4_status_cache[make_key(path)]
end

function M.clear()
    p4_status_cache = {}
end

-- ======================================================
-- 同期アクション (自動チェックアウト用)
-- ======================================================

-- 指定したファイルをCheckout(Edit)する
function M.edit(path)
    local key = make_key(path)
    -- 同期実行 (vim.fn.system)
    local output = vim.fn.system("p4 edit " .. vim.fn.shellescape(path))
    
    -- 成功したらキャッシュを即時更新してUI反応を良くする
    if vim.v.shell_error == 0 then
        p4_status_cache[key] = "M"
        vim.notify("[UNX] P4 Checked out: " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO)
        return true
    else
        vim.notify("[UNX] P4 Checkout Failed:\n" .. output, vim.log.levels.ERROR)
        return false
    end
end

-- 指定したファイルをRevertする
function M.revert(path)
    local key = make_key(path)
    local output = vim.fn.system("p4 revert " .. vim.fn.shellescape(path))
    
    if vim.v.shell_error == 0 then
        p4_status_cache[key] = nil
        vim.notify("[UNX] P4 Reverted: " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO)
        return true
    else
        vim.notify("[UNX] P4 Revert Failed:\n" .. output, vim.log.levels.ERROR)
        return false
    end
end

function M.is_managed(path)
    if not path or path == "" then return false end
    
    -- "p4 files" はファイルがDepotにあるか確認します
    -- -m1 は「最新リビジョン1つだけ」という意味で高速化用
    local cmd = "p4 files -m1 " .. vim.fn.shellescape(path)
    local output = vim.fn.system(cmd)
    
    -- エラーコード0 かつ "no such file" などのエラーメッセージがない場合のみ True
    if vim.v.shell_error == 0 and output and output ~= "" then
        if output:match("no such file") or output:match("not on client") then
            return false
        end
        return true
    end
    
    return false
end


function M.get_changes()
    local changes = {}
    for path, status in pairs(p4_status_cache) do
        table.insert(changes, { path = path, status = status })
    end
    return changes
end
return M

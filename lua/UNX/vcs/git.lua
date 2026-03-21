-- lua/UNX/vcs/git.lua
local unl_git = require("UNL.vcs.git")
local unl_path = require("UNL.path")
local M = {}

-- Proxy calls to UNL.vcs.git
setmetatable(M, { __index = unl_git })

-- Use ASCII Unit Separator to avoid conflicts with commit messages
local SEP = string.char(0x1f)

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
        vim.schedule(function() on_success(nil) end)
    end
end

--- Find git root from a given directory
--- @param cwd string Starting directory
--- @param callback function(git_root: string|nil)
local function find_git_root(cwd, callback)
    spawn_git({"rev-parse", "--show-toplevel"}, cwd, function(output)
        if not output then return callback(nil) end
        local root = output:gsub("[\r\n]+", "")
        if root == "" then return callback(nil) end
        callback(unl_path.normalize(root))
    end)
end

--- Get current user name
--- @param cwd string
--- @param callback function(name: string|nil)
function M.get_user_name(cwd, callback)
    spawn_git({"config", "user.name"}, cwd, function(output)
        if not output then return callback(nil) end
        local name = output:gsub("[\r\n]+", "")
        if name == "" then return callback(nil) end
        callback(name)
    end)
end

--- Get git log (newest first)
--- @param cwd string Root directory
--- @param limit number Max count
--- @param author string|nil Author filter (optional)
--- @param callback function(commits: table[]|nil)
function M.get_log(cwd, limit, author, callback)
    find_git_root(cwd, function(git_root)
        if not git_root then return callback(nil) end

        local format = "%h" .. SEP .. "%s" .. SEP .. "%an" .. SEP .. "%ar"
        local args = { "log", "--first-parent", "--pretty=format:" .. format, "-n", tostring(limit) }
        if author then
            table.insert(args, "--author=" .. author)
        end

        spawn_git(args, git_root, function(output)
            if not output then return callback(nil) end

            local commits = {}
            for line in output:gmatch("[^\r\n]+") do
                local parts = vim.split(line, SEP)
                if #parts >= 4 then
                    table.insert(commits, {
                        hash = parts[1],
                        message = parts[2],
                        author = parts[3],
                        date = parts[4],
                        display = string.format("%s %s (%s)", parts[1], parts[2], parts[4]),
                        vcs = "git",
                        _root = git_root,
                    })
                end
            end
            callback(commits)
        end)
    end)
end

--- Get changed files for a commit
--- @param cwd string Root directory
--- @param commit_hash string Commit hash
--- @param callback function(files: string[]|nil)
function M.get_commit_files(cwd, commit_hash, callback)
    find_git_root(cwd, function(git_root)
        if not git_root then return callback(nil) end

        spawn_git({"show", "--name-only", "--pretty=format:", commit_hash}, git_root, function(output)
            if not output then return callback(nil) end

            local files = {}
            for line in output:gmatch("[^\r\n]+") do
                if line ~= "" then
                    table.insert(files, line)
                end
            end
            callback(files)
        end)
    end)
end

return M

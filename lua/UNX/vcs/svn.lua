-- lua/UNX/vcs/svn.lua
local unl_svn = require("UNL.vcs.svn")
local unl_path = require("UNL.path")
local M = {}

-- Proxy calls to UNL.vcs.svn
setmetatable(M, { __index = unl_svn })

local function spawn_svn(args, cwd, on_success)
    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)
    local output_data = ""

    local handle, pid
    handle, pid = vim.loop.spawn("svn", {
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

--- Get current SVN user name
--- @param cwd string
--- @param callback function(name: string|nil)
function M.get_user_name(cwd, callback)
    spawn_svn({ "info", "--show-item", "wc-root" }, cwd, function(output)
        if not output then return callback(nil) end
        -- Try to get from auth cache via svn log of last commit
        spawn_svn({ "log", "-l", "1", "--xml" }, cwd, function(log_output)
            if not log_output then return callback(nil) end
            local author = log_output:match("<author>([^<]+)</author>")
            callback(author)
        end)
    end)
end

--- Get SVN log
--- @param cwd string Root directory
--- @param limit number Max count
--- @param author string|nil Author filter (optional)
--- @param callback function(commits: table[]|nil)
function M.get_log(cwd, limit, author, callback)
    -- Check if SVN working copy exists first
    spawn_svn({ "info", "--show-item", "wc-root" }, cwd, function(wc_output)
        if not wc_output then return callback(nil) end

        -- Fetch more if filtering by author (SVN doesn't have --author flag)
        local fetch_limit = author and tostring(limit * 5) or tostring(limit)
        local args = { "log", "-l", fetch_limit, "--xml" }

        spawn_svn(args, cwd, function(output)
            if not output then return callback(nil) end

            local commits = {}
            for entry in output:gmatch("<logentry(.-)</logentry>") do
                local rev = entry:match('revision="(%d+)"')
                local entry_author = entry:match("<author>([^<]*)</author>") or ""
                local date_str = entry:match("<date>([^<]*)</date>") or ""
                local msg = entry:match("<msg>([^<]*)</msg>") or "(no message)"

                if rev then
                    local include = true
                    if author and entry_author ~= author then
                        include = false
                    end

                    if include and #commits < limit then
                        local rel_date = date_str
                        local y, mo, d, h, mi, s = date_str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
                        if y then
                            local ts = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
                            local diff = os.time() - ts
                            if diff < 3600 then
                                rel_date = math.floor(diff / 60) .. " minutes ago"
                            elseif diff < 86400 then
                                rel_date = math.floor(diff / 3600) .. " hours ago"
                            else
                                rel_date = math.floor(diff / 86400) .. " days ago"
                            end
                        end

                        table.insert(commits, {
                            hash = "r" .. rev,
                            message = vim.fn.trim(msg),
                            author = entry_author,
                            date = rel_date,
                            display = string.format("r%s %s (%s)", rev, vim.fn.trim(msg), rel_date),
                            vcs = "svn",
                            _rev = rev,
                        })
                    end
                end
            end

            callback(commits)
        end)
    end)
end

--- Get changed files for an SVN revision
--- @param cwd string Root directory
--- @param revision string Revision (e.g. "r123")
--- @param callback function(files: string[]|nil)
function M.get_commit_files(cwd, revision, callback)
    -- Strip "r" prefix if present
    local rev = revision:gsub("^r", "")
    local args = { "log", "-r", rev, "-v", "--xml" }

    spawn_svn(args, cwd, function(output)
        if not output then return callback(nil) end

        local files = {}
        -- Parse <path> entries from <paths>...</paths>
        for path_entry in output:gmatch("<path(.-)</path>") do
            local path = path_entry:match(">(.+)$")
            if path then
                table.insert(files, path)
            end
        end

        callback(files)
    end)
end

return M

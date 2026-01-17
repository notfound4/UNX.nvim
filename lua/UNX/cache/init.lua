-- lua/UNX/cache/init.lua

local fs = require("vim.fs")
local unl_path = require("UNL.path")
local logger = require("UNX.logger")

local M = {}

-- ======================================================
-- PRIVATE
-- ======================================================

local function get_cache_dir()
    local cache_dir = fs.joinpath(vim.fn.stdpath("cache"), "unx")
    if vim.fn.isdirectory(cache_dir) == 0 then
        vim.fn.mkdir(cache_dir, "p")
    end
    return cache_dir
end

local function get_project_cache_key(project_root)
    if not project_root then return nil end
    -- Windowsパスのコロンやスラッシュを置換
    return project_root:gsub(":", ""):gsub("/", "_"):gsub("\\", "_")
end

local function get_cache_filepath(project_root, file_id)
    local project_key = get_project_cache_key(project_root)
    if not project_key then return nil end
    
    local cache_dir = get_cache_dir()
    return fs.joinpath(cache_dir, string.format("%s_%s.json", project_key, file_id))
end

-- ======================================================
-- PUBLIC
-- ======================================================

---
-- Reads data from a project-specific cache file.
--
--@param file_id string A unique identifier for the cache file (e.g., "tree_state").
--@param project_root string The absolute path to the project root.
--@return table|nil The decoded JSON data, or nil if the file doesn't exist or an error occurs.
function M.read(file_id, project_root)
    local filepath = get_cache_filepath(project_root, file_id)
    if not filepath then
        logger.debug("Could not generate cache filepath for reading. project_root: %s", project_root)
        return nil
    end

    local file = io.open(filepath, "r")
    if not file then return nil end

    local content = file:read("*a")
    file:close()

    if not content or content == "" then return nil end

    local ok, data = pcall(vim.fn.json_decode, content)
    if not ok then
        logger.warn("Failed to decode JSON from cache file: %s", filepath)
        return nil
    end

    return data
end

---
-- Writes data to a project-specific cache file.
--
--@param file_id string A unique identifier for the cache file (e.g., "tree_state").
--@param project_root string The absolute path to the project root.
--@param data table The Lua table to be encoded as JSON and saved.
function M.write(file_id, project_root, data)
    local filepath = get_cache_filepath(project_root, file_id)
    if not filepath then
        logger.debug("Could not generate cache filepath for writing. project_root: %s", project_root)
        return
    end

    local json_str = vim.fn.json_encode(data)

    local file = io.open(filepath, "w")
    if not file then
        logger.warn("Failed to open cache file for writing: %s", filepath)
        return
    end

    file:write(json_str)
    file:close()
end

return M

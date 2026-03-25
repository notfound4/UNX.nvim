-- lua/UNX/cache/favorites.lua
local unx_config = require("UNX.config")
local unl_cache_core = require("UNL.cache.core")
local fs = require("vim.fs")
local unl_finder = require("UNL.finder")
local unl_path = require("UNL.path")

local M = {}

local CACHE_FILENAME_SUFFIX = "_favorites.json"

-- プロジェクト固有のキャッシュパスを取得
local function get_cache_path(project_root)
  -- 1. 指定がなければ現在のディレクトリからプロジェクトルートを特定
  project_root = project_root or unl_finder.project.find_project_root(vim.loop.cwd())
  if not project_root then return nil end

  -- 2. プロジェクトルートのパスをユニークな文字列に変換
  local safe_project_name = unl_path.normalize(project_root):gsub("[\\/:]", "_")
  
  -- 3. UNXの設定からキャッシュディレクトリを取得
  local conf = unx_config.get()
  local base_dir = unl_cache_core.get_cache_dir(conf)
  if not base_dir then return nil end

  return fs.joinpath(base_dir, safe_project_name .. CACHE_FILENAME_SUFFIX)
end

function M.load(project_root)
  local path = get_cache_path(project_root)
  if not path or vim.fn.filereadable(path) == 0 then
    return {}
  end
  local data = unl_cache_core.load_json(path)
  return data or {}
end

function M.save(data, project_root)
  local path = get_cache_path(project_root)
  if not path then return false end
  
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  return unl_cache_core.save_json(path, data)
end

--- トグル機能: 既にあれば削除、なければ追加
function M.toggle(target_path, project_root, folder_name)
  if not target_path or target_path == "" then return false, "Invalid path" end
  
  local favorites = M.load(project_root)
  local found_idx = nil
  local norm_target = unl_path.normalize(target_path)

  -- 重複チェック
  for i, item in ipairs(favorites) do
    if not item.is_folder and unl_path.normalize(item.path) == norm_target then
      found_idx = i
      break
    end
  end

  if found_idx then
    table.remove(favorites, found_idx)
    M.save(favorites, project_root)
    return false, "Removed from Favorites"
  else
    table.insert(favorites, {
      path = target_path,
      name = vim.fn.fnamemodify(target_path, ":t"),
      folder = folder_name or "Default",
      added_at = os.time()
    })
    M.save(favorites, project_root)
    return true, "Added to Favorites"
  end
end

function M.add_folder(folder_name, project_root)
  if not folder_name or folder_name == "" then return false end
  local favorites = M.load(project_root)
  
  -- 重複チェック
  for _, item in ipairs(favorites) do
    if item.is_folder and item.name == folder_name then
      return false, "Folder already exists"
    end
  end
  
  table.insert(favorites, {
    is_folder = true,
    name = folder_name,
    added_at = os.time()
  })
  M.save(favorites, project_root)
  return true
end

function M.remove_folder(folder_name, project_root)
    local favorites = M.load(project_root)
    local new_list = {}
    for _, item in ipairs(favorites) do
        if not (item.is_folder and item.name == folder_name) then
            -- フォルダ削除時、中身は Default に戻す
            if item.folder == folder_name then
                item.folder = "Default"
            end
            table.insert(new_list, item)
        end
    end
    M.save(new_list, project_root)
end

function M.move_to_folder(target_path, folder_name, project_root)
    local favorites = M.load(project_root)
    local norm_target = unl_path.normalize(target_path)
    for _, item in ipairs(favorites) do
        if not item.is_folder and unl_path.normalize(item.path) == norm_target then
            item.folder = folder_name
            break
        end
    end
    M.save(favorites, project_root)
end

function M.rename_folder(old_name, new_name, project_root)
    if not new_name or new_name == "" or old_name == new_name then return false end
    local favorites = M.load(project_root)
    
    for _, item in ipairs(favorites) do
        if item.is_folder and item.name == old_name then
            item.name = new_name
        elseif item.folder == old_name then
            item.folder = new_name
        end
    end
    M.save(favorites, project_root)
    return true
end

function M.get_folders(project_root)
    local favorites = M.load(project_root)
    local folders = { "Default" }
    for _, item in ipairs(favorites) do
        if item.is_folder then
            table.insert(folders, item.name)
        end
    end
    return folders
end

return M

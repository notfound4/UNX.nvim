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
function M.toggle(target_path, project_root)
  if not target_path or target_path == "" then return false, "Invalid path" end
  
  local favorites = M.load(project_root)
  local found_idx = nil
  local norm_target = unl_path.normalize(target_path)

  -- 重複チェック
  for i, item in ipairs(favorites) do
    if unl_path.normalize(item.path) == norm_target then
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
      added_at = os.time()
    })
    M.save(favorites, project_root)
    return true, "Added to Favorites"
  end
end

return M

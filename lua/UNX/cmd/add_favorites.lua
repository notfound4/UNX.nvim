local unl_api = require("UNL.api")
local unl_picker = require("UNL.backend.picker")
local favorites_cache = require("UNX.cache.favorites")
local unl_path = require("UNL.path")
local unx_config = require("UNX.config")

local M = {}

function M.execute(opts)
  opts = opts or {}
  
  -- Use UNL Server to get all files
  unl_api.db.get_all_file_paths(function(paths)
      if not paths or #paths == 0 then
          return vim.notify("No files found in UNL Server DB. Run :UNL refresh.", vim.log.levels.WARN)
      end
      
      local picker_items = {}
      for _, path in ipairs(paths) do
          table.insert(picker_items, {
              display = vim.fn.fnamemodify(path, ":."), 
              value = path,
              filename = path, 
          })
      end
      
      local title = "Add to Favorites (UNL Server)"

      unl_picker.pick({        kind = "unx_favorites_add",
        title = title,
        items = picker_items,
        conf = unx_config.get(),
        preview_enabled = true,
        devicons_enabled = true,
        multi_select = true,
        
        on_submit = function(selections)
          if not selections then return end
          local targets = (type(selections) == "table" and selections) or { selections }
          
          local count = 0
          local project_root = require("UNL.finder").project.find_project_root(vim.loop.cwd())
          local current_list = favorites_cache.load(project_root)
          
          for _, sel in ipairs(targets) do
             local path = (type(sel) == "table" and sel.value) or sel
             local exists = false
             local norm_path = unl_path.normalize(path)
             for _, fav in ipairs(current_list) do
                 if unl_path.normalize(fav.path) == norm_path then exists = true break end
             end
             
             if not exists then
                 favorites_cache.toggle(path, project_root)
                 count = count + 1
             end
          end
          
          if count > 0 then
              vim.notify(string.format("Added %d items to Favorites.", count), vim.log.levels.INFO)
              -- ビューが開いていれば更新
              local ok_exp, explorer = pcall(require, "UNX.ui.explorer")
              if ok_exp and explorer.is_open() then
                  explorer.refresh()
              end
          else
              vim.notify("Selected items were already in Favorites.", vim.log.levels.INFO)
          end
        end,
      })
  end)
end

return M

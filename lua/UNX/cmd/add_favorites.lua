local unl_picker = require("UNL.backend.picker")
local favorites_cache = require("UNX.cache.favorites")
local unl_path = require("UNL.path")
local unl_api = require("UNL.api")
local unx_config = require("UNX.config")

local M = {}

function M.execute(opts)
  opts = opts or {}
  
  local request_scope = opts.scope or "full"
  local request_deps = opts.deps_flag or "--deep-deps"

  -- UEPからファイルリスト（表示用整形済み）を取得
  unl_api.provider.request("uep.get_project_items", { 
      scope = request_scope,
      deps_flag = request_deps
  }, function(ok, items)
      
      if not ok or not items or #items == 0 then
          local msg = type(items) == "string" and items or "No files found in UEP cache. Run :UEP refresh."
          return vim.notify("Favorites Add Error: " .. msg, vim.log.levels.WARN)
      end
      
      local picker_items = {}
      for _, item in ipairs(items) do
          -- UEP側で作られた display をそのまま使う (高速)
          local display_text = item.display or item.path
          
          table.insert(picker_items, {
              display = display_text, 
              value = item.path,
              filename = item.path, 
          })
      end
      
      local title = string.format("Add to Favorites (UEP: %s)", request_scope)

      unl_picker.pick({
        kind = "unx_favorites_add",
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
          local current_list = favorites_cache.load()
          
          for _, sel in ipairs(targets) do
             local path = (type(sel) == "table" and sel.value) or sel
             local exists = false
             local norm_path = unl_path.normalize(path)
             for _, fav in ipairs(current_list) do
                 if unl_path.normalize(fav.path) == norm_path then exists = true break end
             end
             
             if not exists then
                 favorites_cache.toggle(path)
                 count = count + 1
             end
          end
          
          if count > 0 then
              vim.notify(string.format("Added %d items to Favorites.", count), vim.log.levels.INFO)
              -- ビューが開いていれば更新
              local ok_ui, ui = pcall(require, "UNX.ui.view.uproject")
              if ok_ui and ui.refresh then ui.refresh(nil) end
          else
              vim.notify("Selected items were already in Favorites.", vim.log.levels.INFO)
          end
        end,
      })
  end)
end

return M

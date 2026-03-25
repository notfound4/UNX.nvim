-- lua/UNX/ui/view/action/favorites.lua
local Input = require("nui.input")
local event = require("nui.utils.autocmd").event
local favorites_cache = require("UNX.cache.favorites")
local ctx_uproject = require("UNX.context.uproject")

local unl_picker = require("UNL.picker")
local unx_config = require("UNX.config")

local M = {}

function M.add_folder(tree)
    local ctx = ctx_uproject.get()
    local project_root = ctx.project_root
    if not project_root then return end

    local input = Input({
        position = "50%",
        size = { width = 40 },
        border = { style = "rounded", text = { top = "[ New Favorite Folder ]", top_align = "center" } },
        win_options = { winblend = 10, winhighlight = "Normal:Normal,FloatBorder:FloatBorder" },
    }, {
        prompt = " Name: ",
        default_value = "",
        on_close = function() end,
        on_submit = function(value)
            if value and value ~= "" then
                local success, err = favorites_cache.add_folder(value, project_root)
                if success then
                    vim.notify(string.format("Created favorite folder: %s", value), vim.log.levels.INFO)
                    -- ツリーをリフレッシュ
                    local explorer_ui = require("UNX.ui.explorer")
                    explorer_ui.refresh()
                else
                    vim.notify(err or "Failed to create folder", vim.log.levels.ERROR)
                end
            end
        end,
    })

    input:mount()
    input:map("n", "<Esc>", function() input:unmount() end, { noremap = true })
end

function M.move_item(tree)
    local node = tree:get_node()
    if not node or not node.extra or not node.extra.is_favorite_item then
        return vim.notify("Select a favorite item to move", vim.log.levels.WARN)
    end

    local ctx = ctx_uproject.get()
    local project_root = ctx.project_root
    if not project_root then return end

    local folders = favorites_cache.get_folders(project_root)
    local items = {}
    for _, f in ipairs(folders) do
        table.insert(items, { label = f, value = f })
    end
    
    unl_picker.open({
        kind = "unx_favorites_move",
        title = "Move to folder",
        items = items,
        conf = unx_config.get(),
        preview_enabled = false,
        on_submit = function(selection)
            if selection then
                local choice = selection
                favorites_cache.move_to_folder(node.path, choice, project_root)
                vim.notify(string.format("Moved %s to %s", node.text, choice), vim.log.levels.INFO)
                local explorer_ui = require("UNX.ui.explorer")
                explorer_ui.refresh()
            end
        end,
    })
end

function M.remove_folder(tree)
    local node = tree:get_node()
    if not node or not node.extra or not node.extra.is_favorite_folder then
        return vim.notify("Select a favorite folder to remove", vim.log.levels.WARN)
    end

    local ctx = ctx_uproject.get()
    local project_root = ctx.project_root
    if not project_root then return end

    vim.ui.select({ "Yes", "No" }, {
        prompt = string.format("Remove folder '%s'? (Items will be moved to Default)", node.text),
    }, function(choice)
        if choice == "Yes" then
            favorites_cache.remove_folder(node.text, project_root)
            local explorer_ui = require("UNX.ui.explorer")
            explorer_ui.refresh()
        end
    end)
end

function M.rename_folder(tree)
    local node = tree:get_node()
    if not node or not node.extra or not node.extra.is_favorite_folder then
        return vim.notify("Select a favorite folder to rename", vim.log.levels.WARN)
    end
    if node.text == "Default" then
        return vim.notify("Cannot rename the Default folder", vim.log.levels.WARN)
    end

    local ctx = ctx_uproject.get()
    local project_root = ctx.project_root
    if not project_root then return end

    local input = Input({
        position = "50%",
        size = { width = 40 },
        border = { style = "rounded", text = { top = "[ Rename Favorite Folder ]", top_align = "center" } },
        win_options = { winblend = 10, winhighlight = "Normal:Normal,FloatBorder:FloatBorder" },
    }, {
        prompt = " New Name: ",
        default_value = node.text,
        on_close = function() end,
        on_submit = function(value)
            if value and value ~= "" and value ~= node.text then
                local success = favorites_cache.rename_folder(node.text, value, project_root)
                if success then
                    vim.notify(string.format("Renamed favorite folder: %s -> %s", node.text, value), vim.log.levels.INFO)
                    local explorer_ui = require("UNX.ui.explorer")
                    explorer_ui.refresh()
                end
            end
        end,
    })

    input:mount()
    input:map("n", "<Esc>", function() input:unmount() end, { noremap = true })
end

return M

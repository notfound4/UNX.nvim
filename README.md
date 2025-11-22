# UNX.nvim

# Unreal Neovim eXplorer 💓 Neovim

`UNX.nvim` is a plugin that provides a logical tree view for Unreal Engine development in Neovim.
It integrates project file structure, real-time C++ symbol outlining, and Unreal Insights profiling data into a single, unified UI.

It acts as the UI frontend for the **Unreal Neovim Plugin Suite**, visualizing data provided by [UEP.nvim](https://github.com/taku25/UEP.nvim), [ULG.nvim](https://github.com/taku25/ULG.nvim), and [UCM.nvim](https://github.com/taku25/UCM.nvim).

[English](README.md) | [日本語 (Japanese)](README_ja.md)

-----

## ✨ Features

  * **Project Explorer (Game & Engine)**:

      * Displays a logical structure based on `.uproject` (Game, Plugins, Engine modules).
      * Uses `UEP.nvim` as a backend to parse accurate module structures.
      * **VCS Integration**: Visualizes file status (Modified, Added, Ignored, etc.) with icons and highlighting.
      * **Live Updates**: Automatically detects file changes and refreshes the view.

  * **Smart C++ Symbol Outline**:

      * Uses Tree-sitter to display the structure of the currently active buffer in a real-time tree view.
      * Specialized for Unreal C++: Identifies and displays icons for `UCLASS`, `USTRUCT`, `UENUM`, `UFUNCTION`, `UPROPERTY`, etc.
      * Organizes symbols by distinction: Public / Protected / Private / Implementation details (`.cpp`).
      * Automatically syncs with your cursor position.

  * **Unreal Insights Integration**:

      * Visualizes profiling data received from `ULG.nvim`.
      * Inspect frame data, function durations, and trace events directly inside Neovim.

  * **File Management (via UCM)**:

      * Perform safe file operations directly from the tree.
      * **Add**: Create new C++ classes (`.h` + `.cpp`) or directories.
      * **Rename/Move**: Uses `UCM.nvim` logic to safely manipulate source files according to Unreal rules.
      * **Delete**: Remove files or directories.

  * **Tabbed Interface**:

      * Seamlessly switch between the **Project/Symbols** view and the **Insights (Profiler)** view using the `<Tab>` key.

## 🔧 Requirements

  * Neovim v0.9.0 or later
  * [**UNL.nvim**](https://github.com/taku25/UNL.nvim) (**Required Library**)
  * [**UEP.nvim**](https://github.com/taku25/UEP.nvim) (**Required Data Provider**)
  * [**nui.nvim**](https://github.com/MunifTanjim/nui.nvim) (**Required UI Component**)
  * [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (Required for Symbol Outline)
  * [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) (Recommended for icons)
  * **Recommended for full functionality:**
      * [**UCM.nvim**](https://github.com/taku25/UCM.nvim) (Required for file Add/Rename/Delete actions)
      * [**ULG.nvim**](https://github.com/taku25/ULG.nvim) (Required for displaying Insights data)

## 🚀 Installation

Install with your favorite plugin manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  'taku25/UNX.nvim',
  dependencies = {
     'taku25/UNL.nvim',
     'taku25/UEP.nvim', -- Required for fetching project structure
     'MunifTanjim/nui.nvim',
     'nvim-tree/nvim-web-devicons',
     'taku25/UCM.nvim', -- Recommended for file manipulation actions
     'taku25/ULG.nvim', -- Recommended for using Insights features
    
    {
      "nvim-treesitter/nvim-treesitter",
      -- event = { "BufReadPre", "BufNewFile" },
      branch = "main",
      lazy = false, 
      build = ":TSUpdate",
      dependencies = {
        "nvim-treesitter/nvim-treesitter-textobjects",
      },
      opts = {
      },

      config = function(_, opts)
        vim.api.nvim_create_autocmd('User', { pattern = 'TSUpdate',
        callback = function()
            local parsers = require('nvim-treesitter.parsers')
            parsers.cpp = {
              install_info = {
                url  = 'https://github.com/taku25/tree-sitter-unreal-cpp',
                revision  = '89f3408b2f701a8b002c9ea690ae2d24bb2aae49',
              },
            }
            parsers.ushader = {
              install_info = {
                url  = 'https://github.com/taku25/tree-sitter-unreal-shader',
                revision  = '26f0617475bb5d5accb4d55bd4cc5facbca81bbd',
              },
            }
        end})
        local langs = { "c", "c_sharp", "cpp", "ushader"  }
        require("nvim-treesitter").install(langs)
        local group = vim.api.nvim_create_augroup('MyTreesitter', { clear = true })
        vim.api.nvim_create_autocmd('FileType', {
          group = group,
          pattern = langs,
          callback = function(args)
            vim.treesitter.start(args.buf)
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end,
        })
      end
    }
  },
  opts = {
    -- Your configuration here
  },
}
```

## ⚙️ Configuration

`UNX.nvim` is highly customizable. Below are the default settings.

```lua
opts = {
    window = {
        position = "left", -- "left" or "right"
        size = {
            width = 35,
        },
    },
    uproject = {
        show_hidden = false,
        icon = {
            expander_open   = "",
            expander_closed = "",
            folder_closed   = "",
            folder_open     = "",
            default_file    = "",
            modified        = "[+] ",
        },
        -- Icons for Git Status
        vcs_icons = {
            Modified  = "",
            Added     = "✚",
            Deleted   = "✖",
            Renamed   = "➜",
            Conflict  = "",
            Untracked = "★",
            Ignored   = "◌",
        },
        ui = {
            -- Components to show on the right side of the file tree
            right_components = {
                "vcs_status",
                "modified_buffer",
            },
        },
    },
    keymaps = {
        -- Explorer navigation
        close = { "q" },
        open = { "<CR>", "o" },
        vsplit = "s",
        split = "i",

        -- File Actions (requires UCM.nvim for some)
        action_add = "a",            -- Add file/class
        action_add_directory = "A",  -- Add directory
        action_delete = "d",         -- Delete
        action_move = "m",           -- Move
        action_rename = "r",         -- Rename
    },
    -- ... other highlights and logging settings
}
```

## ⚡ Usage

### Commands

  * **:UNX open** - Open the explorer window.
  * **:UNX close** - Close the explorer window.
  * **:UNX toggle** - Toggle the explorer window.
  * **:UNX refresh** - Manually refresh the file tree and Git status.

### Default Keymaps (Inside UNX Window)

  * `<CR>` or `o`: Open file / Toggle folder.
  * `<Tab>`: Switch between **Project/Symbols** view and **Insights** view.
  * `a`: Add a new C++ class or file (Integrates with `UCM` to handle `.generated.h` etc).
  * `A`: Add a new directory.
  * `d`: Delete file or directory.
  * `r`: Rename (Executes smart rename for C++ classes).
  * `m`: Move.
  * `q`: Close the window.

## 🤝 Integration

`UNX.nvim` works best when the entire Unreal plugin suite is installed.

  * **UEP.nvim**: Provides the backend project data. UNX visualizes what UEP scans.
  * **UCM.nvim**: Handles logic for creating, moving, and renaming C++ classes, ensuring integrity within the Unreal Engine project.
  * **ULG.nvim**: Feeds profiling and trace data into the UNX Insights view.

## 📜 License

MIT License

Copyright (c) 2025 taku25

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

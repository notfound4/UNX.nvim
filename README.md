# UNX.nvim

# Unreal Neovim eXplorer 💓 Neovim
<img width="1220" height="818" alt="unx-main" src="https://github.com/user-attachments/assets/1fa91f76-bd2f-4fcc-8166-c67789dee83a" />

`UNX.nvim` is a dedicated side-panel explorer optimized for Unreal Engine development in Neovim.
It unifies project file structure, real-time C++ symbol outlines, resolved configuration values, and Unreal Insights profiling data into a single, powerful UI.

It serves as the comprehensive UI frontend for the **Unreal Neovim Plugin Suite**, visualizing data provided by [UEP.nvim](https://github.com/taku25/UEP.nvim), [ULG.nvim](https://github.com/taku25/ULG.nvim), and [UCM.nvim](https://github.com/taku25/UCM.nvim).

[English](README.md) | [日本語 (Japanese)](README_ja.md)

-----

## ✨ Features

  * **Project Explorer (Game & Engine)**:
      * **Logical Structure**: Displays a clean hierarchy based on `.uproject` (Game, Plugins, Engine modules) without physical folder clutter.
      * **Favorites**: Bookmark frequently used files or folders to the top of the tree (`b` key).
      * **VCS Integration (Git & Perforce)**:
          * **Pending Changes**: Instantly access currently modified or staged files at the very top.
          * **Unpushed Commits**: (Git only) View files committed but not yet pushed to the remote.
          * **Auto Checkout**: Automatically prompts to checkout read-only files (P4) upon editing.
      * **File Operations**: Create classes, rename (smart refactor via UCM), move, and delete files directly from the tree.

  * **Smart C++ Symbol Outline**:
      * Displays a real-time tree of the active buffer's structure using a custom Tree-sitter parser.
      * **Unreal Specific**: Identifies `UCLASS`, `USTRUCT`, `UENUM`, `UFUNCTION`, `UPROPERTY` with distinct icons.
      * Organized by access specifier (Public/Protected/Private) and separates implementation (`.cpp`) details.

  * **Config Explorer**:
      * A dedicated tab to explore resolved `.ini` configuration values.
      * Visualize how values are overridden across layers (Base -> Engine -> Project -> Platform -> User).

  * **Unreal Insights Integration**:
      * Visualizes profiling data received from `ULG.nvim`.
      * Inspect frame data, function durations, and trace events directly inside Neovim without leaving the editor.

  * **Tabbed Interface**:
      * Seamlessly switch between **Project** (`uproject`), **Config** (`config`), and **Insights** (`insights`) views using the `<Tab>` key.

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
      branch = "main",
      lazy = false, 
      build = ":TSUpdate",
      dependencies = {
        "nvim-treesitter/nvim-treesitter-textobjects",
      },
      config = function(_, opts)
        -- Configure custom parsers for Unreal C++ and Shaders
        -- (See UEP.nvim or README for detailed parser setup)
        require("nvim-treesitter.configs").setup(opts)
      end
    }
  },
  opts = {
    -- Your configuration here
  },
}
````

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
        -- Icons for VCS Status
        vcs_icons = {
            Modified  = "",
            Added     = "✚",
            Deleted   = "✖",
            Renamed   = "➜",
            Conflict  = "",
            Untracked = "★",
            Ignored   = "◌",
        },
    },
    -- Version Control System Settings
    vcs = {
        git = { enabled = true },
        p4 = { 
            enabled = true,
            auto_checkout = true, -- Automatically checkout read-only files on edit
        },
    },
    keymaps = {
        -- Explorer navigation
        close = { "q" },
        open = { "<CR>", "o" },
        vsplit = "s",
        split = "i",

        -- Actions
        action_add = "a",            -- Add file/class
        action_add_directory = "A",  -- Add directory
        action_delete = "d",         -- Delete
        action_move = "m",           -- Move
        action_rename = "r",         -- Rename
        action_toggle_favorite = "b", -- Toggle Favorite (Bookmark)
        action_diff = "D",            -- Diff against base (VCS)
        action_open_in_ide = "<C-o>"  -- Open in Unreal Editor
    },
}
```

## ⚡ Usage

### Commands

  * **:UNX open** - Open the explorer window.
  * **:UNX close** - Close the explorer window.
  * **:UNX toggle** - Toggle the explorer window.
  * **:UNX focus** - Reveal and focus the current file in the tree.
  * **:UNX refresh** - Manually refresh the file tree and VCS status.

### Default Keymaps (Inside UNX Window)

| Key | Description |
| :--- | :--- |
| `<CR>` / `o` | Open file or toggle directory. |
| `<C-o>` | **Open in Editor**: Open the selected file in the Unreal Editor. |
| `<Tab>` | Cycle through **Project** -\> **Config** -\> **Insights** tabs. |
| `b` | **Bookmark**: Toggle the current item in the "Favorites" list. |
| `/` | **Filter**: Search and filter the tree by filename (maintains hierarchy). |
| `D` | **Diff**: Open a diff view against the VCS base version. |
| `a` | Add a new C++ class or file (Integrates with `UCM` for templates). |
| `A` | Add a new directory. |
| `d` | Delete file or directory (Removes from Favorites if used on a bookmark). |
| `r` | Rename (Executes smart rename for C++ classes via UCM). |
| `m` | Move file or directory. |
| `q` | Close the window. |

## 🤝 Integration

`UNX.nvim` acts as the hub for the entire Unreal plugin suite.

  * **UEP.nvim**: Provides the backbone project data and caching.
  * **UCM.nvim**: Handles logic for creating, moving, renaming, and generating code for C++ classes.
  * **ULG.nvim**: Feeds profiling and trace data into the Insights view.
  * **UEA.nvim**: Provides asset search capabilities and copy reference actions.

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

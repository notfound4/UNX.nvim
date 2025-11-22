# UNX.nvim

# Unreal Neovim eXplorer 💓 Neovim

`UNX.nvim` は、NeovimでのUnreal Engine開発のためのロジカルツリービューを提供するプラグインです
プロジェクトのファイル構造、リアルタイムのC++シンボルアウトライン、そしてUnreal Insightsのプロファイリングデータを、統一されたUIに統合します。

これは **Unreal Neovim Plugin Suite** のUIフロントエンドとして機能し、[UEP.nvim](https://github.com/taku25/UEP.nvim)、[ULG.nvim](https://github.com/taku25/ULG.nvim)、[UCM.nvim](https://github.com/taku25/UCM.nvim) が提供するデータを可視化します。

[English](README.md) | [日本語 (Japanese)](README_ja.md)

-----

## ✨ 機能 (Features)

* **プロジェクトエクスプローラー (Game & Engine)**:
    * `.uproject` に基づく論理的な構造（Game、Plugins、Engineモジュール）を表示します。
    * `UEP.nvim` をバックエンドに使用し、正確なモジュール構造を解析します。
    * **VCS統合**: ファイルのステータス（変更、追加、無視など）をアイコンとハイライトで可視化します。
    * **ライブ更新**: ファイルの変更を検知して自動的にリフレッシュします。

* **スマートC++シンボルアウトライン**:
    * Tree-sitterを使用し、現在アクティブなバッファの構造をリアルタイムでツリー表示します。
    * Unreal C++に特化しており、`UCLASS`、`USTRUCT`、`UENUM`、`UFUNCTION`、`UPROPERTY` などを識別してアイコン表示します。
    * Public / Protected / Private / 実装詳細 (`.cpp`) を区別して整理します。
    * カーソル位置と自動的に同期します。

* **Unreal Insights 統合**:
    * `ULG.nvim` から受信したプロファイリングデータを可視化します。
    * フレームデータ、関数の実行時間、トレースイベントをNeovim内で直接確認できます。

* **ファイル管理 (UCM連携)**:
    * ツリー上から直接、安全なファイル操作を実行できます。
    * **追加 (Add)**: 新しいC++クラス（`.h` + `.cpp`）やディレクトリを作成します。
    * **リネーム/移動 (Rename/Move)**: `UCM.nvim` のロジックを使用し、Unrealのルールに従ってソースファイルを安全に操作します。
    * **削除 (Delete)**: ファイルやディレクトリを削除します。

* **タブインターフェース**:
    * **プロジェクト/シンボル** ビューと **インサイト (プロファイラー)** ビューを `<Tab>` キーでシームレスに切り替え可能です。

## 🔧 必要要件 (Requirements)

* Neovim v0.9.0 以上
* [**UNL.nvim**](https://github.com/taku25/UNL.nvim) (**必須ライブラリ**)
* [**UEP.nvim**](https://github.com/taku25/UEP.nvim) (**必須データプロバイダ**)
* [**nui.nvim**](https://github.com/MunifTanjim/nui.nvim) (**必須UIコンポーネント**)
* [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (シンボル表示に必須)
* [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) (アイコン表示に推奨)
* **フル機能のための推奨プラグイン:**
    * [**UCM.nvim**](https://github.com/taku25/UCM.nvim) (ファイルの追加/リネーム/削除アクションに必要)
    * [**ULG.nvim**](https://github.com/taku25/ULG.nvim) (Insightsビューのデータ表示に必要)

## 🚀 インストール (Installation)

お好みのプラグインマネージャーでインストールしてください。

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  'taku25/UNX.nvim',
  dependencies = {
     'taku25/UNL.nvim',
     'taku25/UEP.nvim', -- プロジェクト構造の取得に必要
     'MunifTanjim/nui.nvim',
     'nvim-tree/nvim-web-devicons',
     'taku25/UCM.nvim', -- ファイル操作アクションを行うなら推奨
     'taku25/ULG.nvim', -- Insights機能を使うなら推奨
    
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
    -- ここに設定を記述
  },
}
````

## ⚙️ 設定 (Configuration)

`UNX.nvim` は高度にカスタマイズ可能です。以下はデフォルト設定の一部です。

```lua
opts = {
    window = {
        position = "left", -- "left" または "right"
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
        -- Gitステータスのアイコン
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
            -- ファイルツリーの右側に表示するコンポーネント
            right_components = {
                "vcs_status",
                "modified_buffer",
            },
        },
    },
    keymaps = {
        -- エクスプローラー操作
        close = { "q" },
        open = { "<CR>", "o" },
        vsplit = "s",
        split = "i",

        -- ファイル操作 (一部 UCM.nvim が必要)
        action_add = "a",            -- ファイル/クラスの追加
        action_add_directory = "A",  -- ディレクトリの追加
        action_delete = "d",         -- 削除
        action_move = "m",           -- 移動
        action_rename = "r",         -- リネーム
    },
    -- ... その他ハイライトやログ設定
}
```

## ⚡ 使い方 (Usage)

### コマンド

  * **:UNX open** - エクスプローラーを開きます。
  * **:UNX close** - エクスプローラーを閉じます。
  * **:UNX toggle** - 開閉をトグルします。
  * **:UNX refresh** - ファイルツリーとGitステータスを手動で更新します。

### デフォルトキーマップ (UNXウィンドウ内)

  * `<CR>` または `o`: ファイルを開く / フォルダの開閉。
  * `<Tab>`: **プロジェクト/シンボル** ビューと **インサイト** ビューを切り替え。
  * `a`: 新しいC++クラスまたはファイルを追加 (`UCM`と連携して`.generated.h`などを考慮)。
  * `A`: 新しいディレクトリを追加。
  * `d`: ファイルまたはディレクトリを削除。
  * `r`: リネーム (C++クラスの場合はスマートリネームを実行)。
  * `m`: 移動。
  * `q`: ウィンドウを閉じる。

## 🤝 連携 (Integration)

`UNX.nvim` は、Unreal関連プラグインスイート全体がインストールされている場合に最高のパフォーマンスを発揮します。

  * **UEP.nvim**: バックエンドのプロジェクトデータを提供します。UNXはUEPがスキャンした内容を可視化します。
  * **UCM.nvim**: C++クラスの作成、移動、名前変更のロジックを処理し、Unreal Engineプロジェクトとして整合性を保ちます。
  * **ULG.nvim**: プロファイリングやトレースデータをUNXのInsightsビューに供給します。

## 📜 ライセンス (License)

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

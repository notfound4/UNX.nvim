# UNX.nvim

# Unreal Neovim eXplorer 💓 Neovim

`UNX.nvim` は、NeovimでのUnreal Engine開発に特化した専用のサイドバーエクスプローラーです。
プロジェクトのファイル構造、リアルタイムのC++シンボルアウトライン、設定値（Config）、そしてUnreal Insightsのプロファイリングデータを、統一されたUIに統合します。

これは **Unreal Neovim Plugin Suite** のUIフロントエンドとして機能し、[UEP.nvim](https://github.com/taku25/UEP.nvim)、[ULG.nvim](https://github.com/taku25/ULG.nvim)、[UCM.nvim](https://github.com/taku25/UCM.nvim) が提供するデータを可視化します。

[English](README.md) | [日本語 (Japanese)](README_ja.md)

-----

## ✨ 機能 (Features)

  * **プロジェクトエクスプローラー (Game & Engine)**:
      * `.uproject` に基づく論理的な構造（Game、Plugins、Engineモジュール）を、物理フォルダの雑多さに惑わされずに表示します。
      * **Favorites (お気に入り)**: よく使うファイルやフォルダを `b` キーでツリーの最上部にブックマークできます。
      * **VCS統合 (Git & Perforce)**:
          * **Pending Changes**: 未コミット（変更中）のファイルへ即座にアクセスできるリストを常時表示します。
          * **Unpushed Commits**: (Gitのみ) コミット済みだがリモートにプッシュしていないファイルを一覧表示します。
          * **Auto Checkout**: P4管理下の読み取り専用ファイルを編集しようとした際、自動でチェックアウトを促します。
      * **ファイル操作**: ツリー上から直接、クラス作成、リネーム、移動、削除を安全に行えます。

  * **スマートC++シンボルアウトライン**:
      * Tree-sitterを使用し、現在アクティブなバッファの構造をリアルタイムでツリー表示します。
      * `UCLASS`, `USTRUCT`, `UFUNCTION` などのUnreal特有のマクロを認識し、専用アイコンで表示します。
      * アクセス指定子 (Public/Private) や実装詳細 (`.cpp`) を区別して整理します。

  * **Config エクスプローラー**:
      * `.ini` 設定ファイルの解決済み値を探索するための専用タブです。
      * Engine -> Project -> Platform -> User と上書きされる設定値の最終結果と履歴を可視化します。

  * **Unreal Insights 統合**:
      * `ULG.nvim` から受信したプロファイリングデータを可視化します。
      * フレームデータ、関数実行時間、トレースイベントをNeovim内で直接確認できます。

  * **タブインターフェース**:
      * **プロジェクト** (`uproject`)、**Config** (`config`)、**インサイト** (`insights`) の各ビューを `<Tab>` キーでシームレスに切り替え可能です。

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
      branch = "main",
      lazy = false, 
      build = ":TSUpdate",
      dependencies = {
        "nvim-treesitter/nvim-treesitter-textobjects",
      },
      config = function(_, opts)
        -- Unreal C++ や Shader 用のパーサー設定
        -- (詳細は UEP.nvim の README 等を参照してください)
        require("nvim-treesitter.configs").setup(opts)
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
    },
    -- バージョン管理システム設定
    vcs = {
        git = { enabled = true },
        p4 = { 
            enabled = true,
            auto_checkout = true, -- 編集時に自動チェックアウトを試みる
        },
    },
    keymaps = {
        -- エクスプローラー操作
        close = { "q" },
        open = { "<CR>", "o" },
        vsplit = "s",
        split = "i",

        -- アクション
        action_add = "a",            -- 追加
        action_add_directory = "A",  -- ディレクトリ追加
        action_delete = "d",         -- 削除
        action_move = "m",           -- 移動
        action_rename = "r",         -- リネーム
        action_toggle_favorite = "b" -- お気に入りトグル
    },
}
```

## ⚡ 使い方 (Usage)

### コマンド

  * **:UNX open** - エクスプローラーを開きます。
  * **:UNX close** - エクスプローラーを閉じます。
  * **:UNX toggle** - 開閉をトグルします。
  * **:UNX refresh** - ファイルツリーとVCSステータスを手動で更新します。

### デフォルトキーマップ (UNXウィンドウ内)

| キー | 説明 |
| :--- | :--- |
| `<CR>` / `o` | ファイルを開く / フォルダの開閉。 |
| `<Tab>` | **Project** -\> **Config** -\> **Insights** タブを切り替え。 |
| `b` | **Bookmark**: カーソル下の項目をお気に入りに追加/解除します。 |
| `a` | 新しいC++クラスまたはファイルを追加 (`UCM`と連携して`.generated.h`などを考慮)。 |
| `A` | 新しいディレクトリを追加。 |
| `d` | ファイルまたはディレクトリを削除 (お気に入り項目の場合はリストから解除)。 |
| `r` | リネーム (C++クラスの場合はスマートリネームを実行)。 |
| `m` | 移動。 |
| `q` | ウィンドウを閉じる。 |

## 🤝 連携 (Integration)

`UNX.nvim` は、Unreal関連プラグインスイート全体がインストールされている場合に最高のパフォーマンスを発揮します。

  * **UEP.nvim**: バックエンドのプロジェクトデータを提供します。UNXはUEPがスキャンした内容を可視化します。
  * **UCM.nvim**: C++クラスの作成、移動、名前変更のロジックを処理し、Unreal Engineプロジェクトとして整合性を保ちます。
  * **ULG.nvim**: プロファイリングやトレースデータをUNXのInsightsビューに供給します。
  * **UEA.nvim**: アセット検索や参照パスのコピー機能を提供します。

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

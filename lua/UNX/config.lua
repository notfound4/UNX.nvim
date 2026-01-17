-- lua/UNX/config.lua

local M = {}

-- UNL の設定システムに登録されている名前
M.name = "UNX"

--- UNLの設定システムからUNXの設定を取得します。
--- UNLは自動的にローカルの.unlrc.json設定をマージします。
--- @return table 現在のUNX設定
M.get = function()
  -- M.name ("UNX") をキーとして、UNLの設定システムを呼び出す
  return require("UNL.config").get(M.name)
end

return M

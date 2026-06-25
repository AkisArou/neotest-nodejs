vim.opt.rtp:append(".")

local pack_root = vim.fn.stdpath("data") .. "/site/pack/core/opt"

for _, plugin in ipairs({
  "plenary.nvim",
  "nvim-nio",
  "nvim-treesitter",
  "neotest",
}) do
  vim.opt.rtp:append(pack_root .. "/" .. plugin)
end

vim.cmd.runtime({ "plugin/plenary.vim", bang = true })

require("neotest").setup({
  log_level = vim.log.levels.WARN,
})

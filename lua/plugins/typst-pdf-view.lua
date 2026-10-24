-- Reuse the installed Snacks viewer; don't render unrelated document images.
---@type LazySpec
return {
  "folke/snacks.nvim",
  opts = { image = { enabled = true, doc = { enabled = false }, math = { enabled = false } } },
}

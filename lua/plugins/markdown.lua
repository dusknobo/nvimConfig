-- Markdown rendering is local to the editor; reuse installed Treesitter/icons.
---@type LazySpec
return {
  {
    "AstroNvim/astrocore",
    opts = {
      treesitter = { ensure_installed = { "markdown", "markdown_inline" } },
    },
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    version = "^8",
    ft = { "markdown" },
    cmd = { "RenderMarkdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.icons" },
    keys = {
      { "<Leader>um", "<Cmd>RenderMarkdown toggle<CR>", desc = "Toggle Markdown rendering" },
    },
    opts = {
      -- Avoid optional TeX executables; this setup renders regular Markdown.
      latex = { enabled = false },
      max_file_size = 2.0,
      completions = { lsp = { enabled = true } },
    },
  },
}

-- Typst compiler and Tinymist are managed outside the Neovim plugin tree.
---@type LazySpec
return {
  {
    "AstroNvim/astrocore",
    opts = function(_, opts)
      require("user.typst").setup()
      opts.filetypes = opts.filetypes or {}
      opts.filetypes.extension = opts.filetypes.extension or {}
      opts.filetypes.extension.typ = "typst"
      opts.treesitter = opts.treesitter or {}
      opts.treesitter.ensure_installed = require("astrocore").list_insert_unique(
        opts.treesitter.ensure_installed, { "typst" }
      )
    end,
  },
  {
    "AstroNvim/astrolsp",
    opts = {
      servers = { "tinymist" },
      config = {
        tinymist = {
          cmd = { vim.fn.expand "~/.local/bin/tinymist", "lsp" },
          root_markers = { "typst.toml", ".git" },
          settings = {
            formatterMode = "typstyle",
            -- PDF output is explicit; opening/typing a document does not write one.
            exportPdf = "never",
          },
        },
      },
    },
  },
}

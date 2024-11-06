-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

---@type LazySpec
return {
  "AstroNvim/astrocommunity",
  -- import/override with your plugins folder
  { import = "astrocommunity.pack.rust" },
  { import = "astrocommunity.pack.bash" },
  { import = "astrocommunity.pack.cpp" },
  { import = "astrocommunity.pack.cmake" },
  { import = "astrocommunity.pack.python" },
  { import = "astrocommunity.pack.julia" },

  --  { import = "astrocommunity.workflow.hardtime-nvim" },
  { import = "astrocommunity.split-and-window.mini-map" },
  { import = "astrocommunity.split-and-window.windows-nvim" },

  { import = "astrocommunity.colorscheme.nordic-nvim" },

  { import = "astrocommunity.git.neogit" },
}

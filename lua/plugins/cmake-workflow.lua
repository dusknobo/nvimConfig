-- Native asynchronous CMake workflow; no additional plugin or automatic builds.
---@type LazySpec
return {
  {
    "AstroNvim/astrocore",
    opts = function(_, opts)
      require("user.cmake").setup()
      opts.mappings = opts.mappings or {}
      opts.mappings.n = opts.mappings.n or {}
      local mappings = {
        ["<Leader>m"] = { desc = "CMake" },
        ["<Leader>mc"] = { function() require("user.cmake").run "configure" end, desc = "CMake configure" },
        ["<Leader>mb"] = { function() require("user.cmake").run "build" end, desc = "CMake build" },
        ["<Leader>mt"] = { function() require("user.cmake").run "test" end, desc = "CMake build and test" },
        ["<Leader>mp"] = { function() require("user.cmake").select_preset() end, desc = "CMake choose preset" },
        ["<Leader>ml"] = { function() require("user.cmake").log() end, desc = "CMake log" },
        ["<Leader>mi"] = { function() require("user.cmake").info() end, desc = "CMake project info" },
        ["<Leader>mx"] = { function() require("user.cmake").stop() end, desc = "CMake stop" },
      }
      for key, mapping in pairs(mappings) do opts.mappings.n[key] = mapping end
    end,
  },
}

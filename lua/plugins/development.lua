-- Local development additions to dusknobo/nvimConfig.
-- Keep the upstream template intact and use the installed system toolchains.
---@type LazySpec
return {
  {
    "AstroNvim/astrocore",
    opts = {
      filetypes = {
        extension = { cppm = "cpp", cxxm = "cpp", ixx = "cpp", mpp = "cpp" },
      },
      treesitter = {
        ensure_installed = { "c", "cpp", "rust", "cmake", "toml", "json", "lua" },
      },
    },
  },
  {
    "AstroNvim/astrolsp",
    opts = {
      servers = { "clangd", "rust_analyzer" },
      formatting = { disabled = { "clangd" } },
      config = {
        clangd = {
          cmd = {
            "/usr/bin/clangd",
            "--background-index",
            "--clang-tidy",
            "--completion-style=detailed",
            "--enable-config",
            "--log=error",
            "--experimental-modules-support",
            "--query-driver=/usr/bin/clang++,/usr/bin/clang,/usr/bin/g++,/usr/bin/gcc",
          },
        },
        rust_analyzer = {
          cmd = { vim.fn.expand "~/.cargo/bin/rust-analyzer" },
          settings = {
            ["rust-analyzer"] = { check = { command = "clippy" }, cargo = { features = "all" } },
          },
        },
      },
    },
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    opts = { ensure_installed = { "lua-language-server" } },
  },
  {
    "nvimtools/none-ls.nvim",
    opts = function(_, opts)
      local null_ls = require "null-ls"
      opts.sources = require("astrocore").list_insert_unique(opts.sources, {
        null_ls.builtins.formatting.clang_format.with { command = "/usr/bin/clang-format" },
      })
    end,
  },
  {
    "mfussenegger/nvim-dap",
    config = function()
      require "astronvim.plugins.configs.nvim-dap"()
      local dap = require "dap"
      dap.adapters.lldb = { type = "executable", command = "/usr/bin/lldb-dap", name = "lldb" }
      local last_programs = {}
      local function project_root()
        local source = vim.api.nvim_buf_get_name(0)
        if source == "" then source = vim.fn.getcwd() end
        return vim.fs.root(source, { "CMakePresets.json", "CMakeUserPresets.json", "Cargo.toml" })
          or vim.fs.root(source, { "CMakeLists.txt", ".git" })
          or vim.fn.getcwd()
      end
      local function executable()
        local root = project_root()
        local default = last_programs[root] or (vim.fn.isdirectory(root .. "/build") == 1 and root .. "/build/" or root .. "/")
        local ok, path = pcall(vim.fn.input, "Executable: ", default, "file")
        if not ok or path == "" then return dap.ABORT end
        if path:sub(1, 2) == "~/" then path = vim.fn.expand("~") .. path:sub(2) end
        if path:sub(1, 1) ~= "/" then path = root .. "/" .. path end
        path = vim.fs.normalize(path)
        local stat = vim.uv.fs_stat(path)
        if not stat or stat.type ~= "file" or vim.fn.executable(path) ~= 1 then
          vim.notify("Not an executable file: " .. path, vim.log.levels.WARN, { title = "LLDB" })
          return dap.ABORT
        end
        last_programs[root] = path
        return path
      end
      local launch = {
        name = "Launch (system LLDB)",
        type = "lldb",
        request = "launch",
        program = executable,
        cwd = project_root,
        disableASLR = false,
        stopOnEntry = false,
        args = {},
      }
      for _, filetype in ipairs { "c", "cpp", "rust" } do
        dap.configurations[filetype] = { vim.deepcopy(launch) }
      end
    end,
  },
}

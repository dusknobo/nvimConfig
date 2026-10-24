-- Small native commands; no extra preview plugin or externally bound service.
local M = {}
local compile_job, preview_job, last_pdf
local preview_log = {}

local function binary(name) return vim.fn.expand("~/.local/bin/" .. name) end
local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Typst" })
end

local function document()
  local source = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype ~= "" or not source:match "%.typ$" then
    notify("Open a .typ source file first", vim.log.levels.WARN)
    return
  end
  if vim.bo.modified then
    notify("Save this buffer with Space w before compiling or previewing", vim.log.levels.WARN)
    return
  end
  local main = vim.b.typst_main or source
  if type(main) ~= "string" or main == "" then
    notify("b:typst_main must be a file path", vim.log.levels.WARN)
    return
  end
  if main:sub(1, 1) ~= "/" then main = vim.fs.dirname(source) .. "/" .. main end
  main = vim.fs.normalize(main)
  if not main:match "%.typ$" or vim.fn.filereadable(main) ~= 1 then
    notify("Save a readable .typ main file first: " .. main, vim.log.levels.WARN)
    return
  end
  local root = vim.fs.root(main, { "typst.toml", ".git" }) or vim.fs.dirname(main)
  return main, root
end

function M.compile(options)
  options = options or {}
  if compile_job then notify("A Typst compilation is already running", vim.log.levels.WARN); return false end
  local main, root = document()
  if not main then return false end
  local pdf = main:gsub("%.typ$", ".pdf")
  local source_win, source_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local ok, job = pcall(vim.system, { binary "typst", "compile", "--root", root, main, pdf }, {
    cwd = root, text = true,
  }, vim.schedule_wrap(function(result)
    compile_job = nil
    if result.code == 0 then
      last_pdf = pdf
      notify("PDF: " .. pdf)
      if options.preview ~= false then
        local shown, view_error = pcall(require("user.typst_pdf").show, pdf, { source_win = source_win, source_buf = source_buf })
        if not shown then notify("PDF compiled, but preview failed: " .. tostring(view_error), vim.log.levels.WARN) end
      end
    else
      notify((result.stderr or result.stdout or "Compilation failed"):sub(1, 8000), vim.log.levels.ERROR)
    end
    if options.on_complete then options.on_complete(result.code == 0, pdf, result) end
  end))
  if not ok then notify(tostring(job), vim.log.levels.ERROR); return false end
  compile_job = job
  return true
end

function M.preview(options)
  options = options or {}
  if preview_job then notify("Preview already running; use :TypstStop before switching documents"); return false end
  local main, root = document()
  if not main then return false end
  local argv = {
    binary "tinymist", "preview", "--root", root,
    "--host", "127.0.0.1:0", "--data-plane-host", "127.0.0.1:0",
    "--control-plane-host", "127.0.0.1:0", "--partial-rendering", "true",
    "--verbose", options.open == false and "--no-open" or "--open", main,
  }
  preview_log = {}
  local function output(_, data)
    for _, line in ipairs(data or {}) do
      if line ~= "" then
        preview_log[#preview_log + 1] = line:sub(1, 2000)
        if #preview_log > 40 then table.remove(preview_log, 1) end
      end
    end
  end
  local job = vim.fn.jobstart(argv, {
    cwd = root, on_stdout = output, on_stderr = output,
    on_exit = function(id, code)
      if preview_job == id then
        preview_job = nil
        if code ~= 0 then
          notify("Preview exited; :TypstInfo shows its last messages", vim.log.levels.WARN)
        end
      end
    end,
  })
  if job <= 0 then notify("Cannot start Tinymist preview", vim.log.levels.ERROR); return false end
  preview_job = job
  notify("Preview started on localhost; save edits to refresh. Stop with :TypstStop")
  return true
end

function M.stop()
  local pdf_closed = require("user.typst_pdf").close()
  if not preview_job then return pdf_closed end
  local job = preview_job
  preview_job = nil
  vim.fn.jobstop(job)
  notify "Preview stopped"
  return true
end

function M.status()
  return {
    preview_job = preview_job, compiling = compile_job ~= nil,
    last_pdf = last_pdf, log = vim.deepcopy(preview_log), pdf = require("user.typst_pdf").status(),
  }
end

function M.setup()
  require("user.typst_pdf").setup()
  local commands = {
    TypstCompile = { function() M.compile() end, "Compile the saved Typst main file to PDF" },
    TypstPreview = { function() M.compile() end, "Compile and preview PDF to the right of Typst source" },
    TypstPdf = { function() M.compile() end, "Compile and preview PDF in Neovim" },
    TypstBrowser = { function() M.preview() end, "Preview saved Typst source in a local browser" },
    TypstStop = { M.stop, "Stop this editor's Typst preview" },
    TypstInfo = { function() notify(vim.inspect(M.status())) end, "Show Typst job state and preview log" },
  }
  for name, spec in pairs(commands) do
    if vim.fn.exists(":" .. name) == 0 then
      vim.api.nvim_create_user_command(name, spec[1], { desc = spec[2] })
    end
  end
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("LocalTypstJobs", { clear = true }),
    callback = function()
      if preview_job then vim.fn.jobstop(preview_job); preview_job = nil end
      if compile_job then compile_job:kill(15); compile_job = nil end
    end,
  })
end

return M

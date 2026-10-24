-- A read-only PDF page to the right of its Typst source, using Kitty graphics.
local M = {}
local uv = vim.uv
local views, serial = {}, 0
local cache
local owned_files = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Typst PDF" })
end

local function current() return views[vim.api.nvim_get_current_tabpage()] end

local function compatible()
  if vim.env.ZELLIJ then
    notify("Run Neovim directly in Kitty, outside Zellij, for PDF graphics", vim.log.levels.WARN)
    return false
  end
  if #vim.api.nvim_list_uis() == 0 then return false end
  if not Snacks.image.supports_terminal() then
    notify("This terminal does not support PDF graphics; use Kitty", vim.log.levels.WARN)
    return false
  end
  return true
end

local function directory()
  if cache then return cache end
  local parent = vim.fn.stdpath "cache" .. "/typst-pdf"
  vim.fn.mkdir(parent, "p", 448)
  cache = parent .. "/" .. vim.fn.getpid() .. "-" .. tostring(uv.hrtime())
  assert(uv.fs_mkdir(cache, 448))
  return cache
end

local function valid(view)
  return view and vim.api.nvim_win_is_valid(view.win) and vim.api.nvim_buf_is_valid(view.buf)
    and vim.api.nvim_win_get_buf(view.win) == view.buf
end

local function spawn(view, argv, generation, callback)
  local ok, job = pcall(vim.system, argv, { text = true, timeout = 20000 }, vim.schedule_wrap(function(result)
    if generation ~= view.generation then return end
    view.job = nil
    if not valid(view) then return end
    if result.code ~= 0 then
      view.rendering = false
      view.error = (result.stderr or "PDF rendering failed"):sub(1, 4000)
      notify(view.error, vim.log.levels.WARN)
      return
    end
    callback(result)
  end))
  if not ok then view.rendering = false; view.error = tostring(job); notify(view.error); return end
  view.job = job
end

local function render(view)
  if not valid(view) then return false end
  if view.job then pcall(view.job.kill, view.job, 15); view.job = nil end
  view.generation = view.generation + 1
  local generation = view.generation
  serial = serial + 1
  local snapshot = directory() .. "/render-" .. serial .. ".pdf"
  local png = directory() .. "/render-" .. serial .. ".png"
  owned_files[snapshot], owned_files[png] = true, true
  local copied, err = uv.fs_copyfile(view.pdf, snapshot)
  if not copied then notify(tostring(err), vim.log.levels.WARN); return false end
  view.rendering, view.error = true, nil
  spawn(view, {
    "/usr/bin/gs", "-q", "-dNODISPLAY", "-dBATCH", "-dSAFER",
    "--permit-file-read=" .. snapshot, "-sPDFname=" .. snapshot,
    "-c", "PDFname (r) file runpdfbegin pdfpagecount = quit",
  }, generation, function(count_result)
    local total = tonumber(vim.trim(count_result.stdout or ""))
    if not total or total < 1 then view.rendering = false; view.error = "Cannot read PDF page count"; return end
    view.pages = total
    view.page = math.max(1, math.min(view.page, total))
    spawn(view, {
      "/usr/bin/gs", "-q", "-dSAFER", "-dBATCH", "-dNOPAUSE",
      "-sDEVICE=png16m", "-r120", "-dTextAlphaBits=4", "-dGraphicsAlphaBits=4",
      "-dFirstPage=" .. view.page, "-dLastPage=" .. view.page,
      "-sOutputFile=" .. png, snapshot,
    }, generation, function()
      -- Unique source path defeats the installed Snacks conversion/image caches.
      -- The old placement is only replaced after a new raster exists.
      view.png, view.snapshot = png, snapshot
      view.rendering = false
      vim.api.nvim_win_call(view.win, function()
        view.placement = Snacks.image.buf._attach(view.buf, {
          src = png,
          on_update = function(placement)
            if generation == view.generation then view.ready = placement:ready() end
          end,
        })
        vim.wo[view.win].winbar = (" PDF %d/%d | [p / ]p pages | r refresh | q close "):format(view.page, total)
      end)
      view.revision = view.revision + 1
    end)
  end)
  return true
end

local function create(source_win)
  local tab = vim.api.nvim_get_current_tabpage()
  local view = views[tab]
  if valid(view) then return view end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "typst-pdf://" .. tab .. "/" .. buf)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "image"
  local win
  vim.api.nvim_win_call(source_win, function()
    vim.cmd "rightbelow vsplit"
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  end)
  view = { win = win, buf = buf, page = 1, pages = 1, revision = 0, generation = 0, source_win = source_win }
  views[tab] = view
  vim.keymap.set("n", "]p", function() M.page(1) end, { buffer = buf, desc = "Next PDF page", silent = true })
  vim.keymap.set("n", "[p", function() M.page(-1) end, { buffer = buf, desc = "Previous PDF page", silent = true })
  vim.keymap.set("n", "r", function() M.refresh() end, { buffer = buf, desc = "Refresh PDF page", silent = true })
  vim.keymap.set("n", "q", function() M.close() end, { buffer = buf, desc = "Close PDF preview", silent = true })
  return view
end

function M.show(pdf, options)
  options = options or {}
  if not compatible() then return false end
  local source_win = options.source_win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(source_win) then return false end
  if vim.api.nvim_win_get_tabpage(source_win) ~= vim.api.nvim_get_current_tabpage() then return false end
  if options.source_buf and vim.api.nvim_win_get_buf(source_win) ~= options.source_buf then return false end
  local view = create(source_win)
  if view.pdf ~= pdf then view.page = 1 end
  view.pdf, view.source_win, view.ready = pdf, source_win, false
  return render(view)
end

function M.page(delta)
  local view = current()
  if not valid(view) or not view.pdf then return false end
  local page = math.max(1, math.min(view.page + delta, view.pages))
  if page == view.page then return false end
  view.page, view.ready = page, false
  return render(view)
end

function M.refresh()
  local view = current()
  if not valid(view) or not view.pdf then return false end
  view.ready = false
  return render(view)
end

function M.close()
  local tab = vim.api.nvim_get_current_tabpage()
  local view = views[tab]
  if not view then return false end
  view.generation = view.generation + 1
  if view.job then pcall(view.job.kill, view.job, 15); view.job = nil end
  if valid(view) then vim.api.nvim_win_close(view.win, false) end
  views[tab] = nil
  return true
end

function M.status()
  local view = current()
  if not view then return nil end
  return {
    open = valid(view) and true or false, pdf = view.pdf, page = view.page, pages = view.pages,
    png = view.png, revision = view.revision, rendering = view.rendering, ready = view.ready,
    source_win = view.source_win, win = view.win, buf = view.buf, error = view.error,
  }
end

function M.setup()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("LocalTypstPdfJobs", { clear = true }),
    callback = function()
      for _, view in pairs(views) do
        view.generation = view.generation + 1
        if view.job then
          pcall(view.job.kill, view.job, 15)
          pcall(view.job.wait, view.job, 500)
        end
      end
      -- Remove only exact generated regular files in our private session folder.
      -- Never recursively remove a cache tree or touch source PDFs.
      if cache and uv.fs_realpath(cache) == cache then
        for path in pairs(owned_files) do
          local name = vim.fs.basename(path)
          local own_name = name:match("^render%-%d+%.pdf$") or name:match("^render%-%d+%.png$")
          local stat = uv.fs_lstat(path)
          if own_name and vim.fs.dirname(path) == cache and stat and stat.type == "file" then uv.fs_unlink(path) end
        end
        uv.fs_rmdir(cache) -- succeeds only if empty; no recursive fallback
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = "LocalTypstPdfJobs",
    callback = function(args)
      for _, view in pairs(views) do
        if view.win == tonumber(args.match) then
          view.generation = view.generation + 1
          if view.job then pcall(view.job.kill, view.job, 15); view.job = nil end
        end
      end
    end,
  })
end

return M

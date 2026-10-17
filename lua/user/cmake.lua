-- Explicit, asynchronous CMake commands; no project files or editor cwd changes.
local M = {}
local uv = vim.uv or vim.loop
local states, selected, stopping = {}, {}, {}
local last_root, configured
local LOG_LINES, LOG_WIDTH = 1500, 8192

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "CMake" })
end

local function absolute(path)
  local value = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  return value == "/" and value or value:gsub("/$", "")
end

local function canonical(path)
  return absolute(uv.fs_realpath(path) or path)
end

local function exists(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "file"
end

local function find_root(explicit)
  if explicit then
    if type(explicit) ~= "string" or explicit == "" then return nil, "Invalid project root" end
    local root = canonical(explicit)
    if vim.fn.isdirectory(root) ~= 1 then return nil, "Project directory does not exist: " .. root end
    return root
  end
  local starts = {}
  local name = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype == "" and name ~= "" then starts[#starts + 1] = vim.fs.dirname(absolute(name)) end
  starts[#starts + 1] = vim.fn.getcwd()
  for _, start in ipairs(starts) do
    for _, markers in ipairs { { "CMakePresets.json", "CMakeUserPresets.json" }, { "CMakeLists.txt" } } do
      local found = vim.fs.find(markers, { path = start, upward = true, type = "file", limit = 1 })[1]
      if found then return canonical(vim.fs.dirname(found)) end
    end
  end
  return nil, "No CMake project found for the current file or working directory"
end

local function append(state, line)
  line = tostring(line):gsub("\r$", ""):gsub("\27%[[%d;]*[A-Za-z]", "")
  if #line > LOG_WIDTH then line = line:sub(1, LOG_WIDTH) .. " [line truncated]" end
  state.lines[#state.lines + 1] = line
  if #state.lines > LOG_LINES then
    local removed = table.remove(state.lines, 1)
    local cwd = removed:match("^@@CMAKE_CWD@@(.+)$")
    if cwd then state.log_start_cwd = cwd end
    state.dropped = state.dropped + 1
  end
end

local function log_lines(state)
  local lines = {
    "CMake: " .. state.root,
    ("Action: %s | phase: %s | running: %s"):format(state.action, state.phase, tostring(state.busy)),
    "Configure preset: " .. (state.preset or "(none; root/build)"),
    "Build directory: " .. (state.binary_dir or "(not configured)"),
    "",
  }
  if state.dropped > 0 then lines[#lines + 1] = ("[%d earlier log lines omitted]"):format(state.dropped) end
  vim.list_extend(lines, state.lines)
  return lines
end

local function show_log(state)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buffer, "cmake-log://" .. buffer)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, log_lines(state))
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "log"
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].readonly = true
  vim.cmd "botright 12split"
  vim.api.nvim_win_set_buf(0, buffer)
end

local function show_failure(state)
  -- %D supplies the command's cwd to the parser, without :cd/:lcd side effects.
  local lines = { "@@CMAKE_CWD@@" .. (state.log_start_cwd or state.root) }
  vim.list_extend(lines, state.lines)
  local efm = table.concat({
    "%D@@CMAKE_CWD@@%f",
    "%E%f:%l:%c: fatal error: %m",
    "%E%f:%l:%c: error: %m",
    "%W%f:%l:%c: warning: %m",
    "%E%f:%l: error: %m",
    "%W%f:%l: warning: %m",
    "%ECMake Error at %f:%l (%m):",
    vim.o.errorformat,
  }, ",")
  local ok, parsed = pcall(vim.fn.getqflist, { lines = lines, efm = efm })
  local items = {}
  if ok then
    for _, item in ipairs(parsed.items or {}) do
      if item.valid == 1 and (item.bufnr or 0) > 0 then items[#items + 1] = item end
    end
  end
  if #items > 0 then
    -- A new history entry preserves the user's previous quickfix list.
    vim.fn.setqflist({}, " ", {
      title = "CMake " .. state.action .. ": " .. state.root,
      items = items,
      context = { owner = "user.cmake", root = state.root },
    })
    vim.cmd "copen"
  else
    show_log(state)
  end
end

local function public_state(state)
  if not state then return nil end
  local result = {}
  for _, key in ipairs {
    "root", "action", "phase", "busy", "job", "preset", "binary_dir", "multi_config",
    "build_config", "success", "cancelled", "exit_code", "message", "dropped", "lines", "commands",
  } do
    result[key] = vim.deepcopy(state[key])
  end
  return result
end

local function finish(state, ok, message, cancelled)
  if not state.busy then return end
  state.busy, state.job, state.success = false, nil, ok
  state.cancelled, state.message = cancelled or false, message
  state.phase = cancelled and "cancelled" or (ok and "done" or "failed")
  append(state, message)
  notify(message, (ok or cancelled) and vim.log.levels.INFO or vim.log.levels.ERROR)
  if not ok and not cancelled then
    local shown, err = pcall(show_failure, state)
    if not shown then notify("Cannot open CMake errors; use :CMakeLog: " .. tostring(err), vim.log.levels.WARN) end
  end
  if state.on_complete then
    local callback = state.on_complete
    state.on_complete = nil
    local callback_ok, err = pcall(callback, ok, public_state(state))
    if not callback_ok then notify("Completion callback failed: " .. tostring(err), vim.log.levels.ERROR) end
  end
end

local function start_job(state, argv, phase, complete)
  if not state.busy then return end
  state.phase = phase
  state.commands[#state.commands + 1] = vim.deepcopy(argv)
  local display = {}
  for _, arg in ipairs(argv) do display[#display + 1] = vim.fn.shellescape(arg) end
  append(state, "@@CMAKE_CWD@@" .. (phase == "build" and state.binary_dir or state.root))
  append(state, "$ " .. table.concat(display, " "))
  local stdout, streams = {}, { out = { partial = "" }, err = { partial = "" } }
  local function emit(stream, is_stdout)
    local line = stream.partial:gsub("\r$", "")
    if is_stdout and not stream.truncated then
      -- Keep only the small preset listing, not the complete process output.
      if phase == "list-presets" and line:match('^%s+"') then
        if #stdout < 256 then stdout[#stdout + 1] = line else state.preset_overflow = true end
      end
      local binary = line:match("^%-%- Build files have been written to: (.+)$")
      if binary then state.configured_binary = binary end
    elseif is_stdout and phase == "list-presets" and stream.truncated then
      state.preset_overflow = true
    end
    if line ~= "" or stream.truncated then
      append(state, line .. (stream.truncated and " [line truncated]" or ""))
    end
    stream.partial, stream.truncated = "", false
  end
  local function output(stream, is_stdout, data)
    if not state.busy or not data then return end
    for index, chunk in ipairs(data) do
      local remaining = LOG_WIDTH - #stream.partial
      stream.partial = stream.partial .. chunk:sub(1, remaining)
      if #chunk > remaining then stream.truncated = true end
      -- The final element is an unfinished line; the next callback continues it.
      if index < #data then emit(stream, is_stdout) end
    end
  end
  local ok, job = pcall(vim.fn.jobstart, argv, {
    cwd = state.root,
    env = { LC_ALL = "C", LANG = "C", CLICOLOR = "0", NO_COLOR = "1" },
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data) output(streams.out, true, data) end,
    on_stderr = function(_, data) output(streams.err, false, data) end,
    on_exit = function(id, code)
      if stopping[state.root] == id then stopping[state.root] = nil end
      if not state.busy then return end
      emit(streams.out, true)
      emit(streams.err, false)
      state.job, state.exit_code = nil, code
      if code ~= 0 then
        finish(state, false, ("CMake %s failed (exit %s); see errors/log"):format(phase, code))
      else
        local completed, err = pcall(complete, stdout)
        if not completed then finish(state, false, "CMake helper error: " .. tostring(err)) end
      end
    end,
  })
  if not ok or type(job) ~= "number" or job <= 0 then
    finish(state, false, "Cannot start " .. argv[1] .. ": " .. tostring(job))
  else
    state.job = job
  end
end

local function presets(state, force_select, callback)
  if not exists(state.root .. "/CMakePresets.json") and not exists(state.root .. "/CMakeUserPresets.json") then
    selected[state.root], state.preset = nil, nil
    callback(nil)
    return
  end
  start_job(state, { "cmake", "--list-presets=configure" }, "list-presets", function(lines)
    if state.preset_overflow then
      finish(state, false, "Configure preset listing exceeded the safe size limit (256 names / 8192 characters per line)")
      return
    end
    local names = {}
    for _, line in ipairs(lines) do
      local name = line:match('^%s+"(.-)"%s+%-') or line:match('^%s+"(.*)"%s*$')
      if name and name ~= "" then names[#names + 1] = name end
    end
    if #names == 0 then
      finish(state, false, "No available configure presets; hidden/disabled presets are not selected")
      return
    end
    local remembered = selected[state.root]
    if not force_select and remembered and vim.tbl_contains(names, remembered) then
      state.preset = remembered
      callback(remembered)
      return
    end
    local function choose(name)
      if not state.busy then return end
      if not name then finish(state, false, "CMake preset selection cancelled", true); return end
      selected[state.root], state.preset = name, name
      callback(name)
    end
    if #names == 1 then
      choose(names[1])
    else
      state.phase = "select-preset"
      vim.ui.select(names, { prompt = "CMake configure preset (" .. state.root .. "):" }, choose)
    end
  end)
end

local function read_cache(state)
  local path = state.binary_dir .. "/CMakeCache.txt"
  if not exists(path) then return false, "Configured build directory has no CMakeCache.txt: " .. path end
  local ok, lines = pcall(vim.fn.readfile, path, "", 20000)
  if not ok then return false, "Cannot read configured CMake cache" end
  state.multi_config = false
  for _, line in ipairs(lines) do
    local configurations = line:match("^CMAKE_CONFIGURATION_TYPES:[^=]*=(.+)$")
    if configurations and configurations ~= "" then state.multi_config = true end
  end
  return true
end

local function build_config()
  local value = vim.g.cmake_build_config or "Debug"
  if type(value) ~= "string" or value == "" or value:find("%z") then return nil end
  return value
end

local function build_jobs()
  local value = vim.g.cmake_build_jobs or 2
  if type(value) ~= "number" or value < 1 or value ~= math.floor(value) then return nil end
  return tostring(value)
end

local function configure(state, preset)
  local argv = { "cmake" }
  if preset then
    vim.list_extend(argv, { "--preset", preset })
  else
    local binary = state.root .. "/build"
    vim.list_extend(argv, { "-S", state.root, "-B", binary })
    -- Do not replace an existing build tree's generator or compiler choices.
    if not exists(binary .. "/CMakeCache.txt") then
      vim.list_extend(argv, { "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Debug" })
    end
  end
  argv[#argv + 1] = "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
  start_job(state, argv, "configure", function()
    local binary = state.configured_binary
    if not binary or binary == "" then
      finish(state, false, "Configure succeeded but CMake did not report its build directory; refusing to guess")
      return
    end
    if binary:sub(1, 1) ~= "/" then binary = state.root .. "/" .. binary end
    state.binary_dir = canonical(binary)
    local cache_ok, cache_error = read_cache(state)
    if not cache_ok then finish(state, false, cache_error); return end
    if state.action == "configure" then
      finish(state, true, "CMake configure completed: " .. state.binary_dir)
      return
    end
    local jobs, configuration = build_jobs(), build_config()
    if not jobs then finish(state, false, "vim.g.cmake_build_jobs must be a positive integer"); return end
    if not configuration then finish(state, false, "vim.g.cmake_build_config must be a nonempty string"); return end
    state.build_config = configuration
    local build = { "cmake", "--build", state.binary_dir, "--parallel", jobs }
    if state.multi_config then vim.list_extend(build, { "--config", configuration }) end
    start_job(state, build, "build", function()
      if state.action == "build" then
        finish(state, true, "CMake build completed: " .. state.binary_dir)
        return
      end
      local test = { "ctest", "--test-dir", state.binary_dir, "--output-on-failure", "--no-tests=error" }
      if state.multi_config then vim.list_extend(test, { "--build-config", configuration }) end
      start_job(state, test, "test", function() finish(state, true, "CMake build and tests completed") end)
    end)
  end)
end

local function begin(action, options)
  options = options or {}
  local root, err = find_root(options.root)
  if not root then
    notify(err, vim.log.levels.WARN)
    if options.on_complete then options.on_complete(false, { message = err, busy = false }) end
    return nil
  end
  if stopping[root] then
    local job = stopping[root]
    local checked, status = pcall(vim.fn.jobwait, { job }, 0)
    if checked and (status[1] >= 0 or status[1] == -3) then
      if stopping[root] == job then stopping[root] = nil end
    else
      local message = "The previous CMake job is still stopping for " .. root .. "; retry after it exits"
      notify(message, vim.log.levels.WARN)
      if options.on_complete then options.on_complete(false, { root = root, message = message, busy = true }) end
      return nil
    end
  end
  if states[root] and states[root].busy then
    local message = "CMake is already running for " .. root .. "; use :CMakeStop first"
    notify(message, vim.log.levels.WARN)
    if options.on_complete then options.on_complete(false, { root = root, message = message, busy = true }) end
    return nil
  end
  local state = {
    root = root, action = action, phase = "starting", busy = true,
    lines = {}, commands = {}, dropped = 0, on_complete = options.on_complete,
  }
  states[root], last_root = state, root
  return state
end

function M.run(action, options)
  if action ~= "configure" and action ~= "build" and action ~= "test" then
    notify("Expected configure, build or test", vim.log.levels.ERROR)
    return false
  end
  local state = begin(action, options)
  if not state then return false end
  presets(state, false, function(preset) configure(state, preset) end)
  return true
end

function M.select_preset(root)
  local state = begin("preset", { root = root })
  if not state then return false end
  presets(state, true, function(preset)
    finish(state, true, "CMake configure preset: " .. (preset or "none; using root/build"))
  end)
  return true
end

local function current_state(root)
  local resolved = find_root(root)
  return states[resolved or (not root and last_root)]
end

function M.state(root)
  return public_state(current_state(root))
end

function M.log(root)
  local state = current_state(root)
  if state then show_log(state) else notify("No CMake run recorded for this project") end
end

function M.info(root)
  local state = current_state(root)
  if not state then notify("No CMake run recorded for this project"); return end
  notify(table.concat({
    "Project: " .. state.root,
    "Configure preset: " .. (state.preset or selected[state.root] or "none"),
    "Build tree: " .. (state.binary_dir or "not configured"),
    "Action/phase: " .. state.action .. "/" .. state.phase,
    "Running: " .. tostring(state.busy),
    "Only configure presets are used; build/test preset-specific targets and environment are not applied.",
    "Use a terminal for workflows that require build/test presets.",
  }, "\n"))
end

function M.stop(root)
  local state = current_state(root)
  if not state or not state.busy then notify("No CMake job is running for this project"); return false end
  local job = state.job
  -- Mark stopped first so any late process/UI callback is ignored.
  if job and job > 0 then stopping[state.root] = job end
  finish(state, false, "CMake operation stopped", true)
  if job and job > 0 then pcall(vim.fn.jobstop, job) end
  return true
end

function M.setup()
  if configured then return end
  configured = true
  local commands = {
    CMakeConfigure = { function() M.run "configure" end, "Configure the current CMake project" },
    CMakeBuild = { function() M.run "build" end, "Configure and build the current CMake project" },
    CMakeTest = { function() M.run "test" end, "Configure, build and test the current CMake project" },
    CMakePreset = { function() M.select_preset() end, "Select an available CMake configure preset" },
    CMakeLog = { function() M.log() end, "Show this project's bounded, in-memory CMake log" },
    CMakeStop = { function() M.stop() end, "Stop only this helper's current project job" },
    CMakeInfo = { function() M.info() end, "Show the current project's CMake state and preset limitations" },
  }
  for name, spec in pairs(commands) do
    if vim.fn.exists(":" .. name) == 0 then
      vim.api.nvim_create_user_command(name, spec[1], { desc = spec[2] })
    else
      notify("Existing command left unchanged: " .. name, vim.log.levels.WARN)
    end
  end
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("UserCMakeJobs", { clear = true }),
    callback = function()
      for _, state in pairs(states) do
        local job = state.busy and state.job
        state.busy = false
        if job and job > 0 then pcall(vim.fn.jobstop, job) end
      end
      for _, job in pairs(stopping) do pcall(vim.fn.jobstop, job) end
    end,
  })
end

return M

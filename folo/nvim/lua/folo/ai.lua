-- AI summaries and translations. Only this module runs Claude or touches summary files.
local M = {}

local TRANSLATION_MARKER = "<!-- folo:translation -->"
local SOURCE_DIR = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
-- lua/folo -> folo/nvim -> repo root; overridable through ai.prompts.
local DEFAULT_PROMPTS = {
  summary = SOURCE_DIR .. "/../../../../native-host/prompts/summary.md",
  translation = SOURCE_DIR .. "/../../../../native-host/prompts/translate.md",
}

-- id -> { summary=, translation= ("queued"|"running"), translate_next=, error= }
local jobs = {}
-- id -> { summary=bool, translation=bool }, read from disk once per change.
local files = {}
local pending = {}
local running = 0
local processes = {}
local listener = function() end

local function config()
  return require("folo").get_config().ai
end

local function changed(id)
  listener(id)
end

function M.on_change(fn)
  listener = fn
end

-- Entry ids come from the network; hashing keeps them out of the path.
function M.path(id)
  local dir = config().dir or (vim.fn.stdpath("cache") .. "/folo/summaries")
  return ("%s/%s.md"):format(dir, vim.fn.sha256(tostring(id)))
end

function M.read(id)
  local path = M.path(id)
  if vim.fn.filereadable(path) == 1 then
    return vim.fn.readfile(path)
  end
end

local function file_state(id)
  if not files[id] then
    local lines = M.read(id)
    files[id] = { summary = lines ~= nil, translation = lines ~= nil and vim.tbl_contains(lines, TRANSLATION_MARKER) }
  end
  return files[id]
end

-- info(id): what the UI shows for this entry.
function M.info(id)
  local job = jobs[id] or {}
  local file = file_state(id)
  return {
    summary = job.summary,
    translation = job.translation,
    error = job.error,
    has_summary = file.summary,
    has_translation = file.translation,
    visible = file.summary or job.summary ~= nil or job.translation ~= nil or job.error ~= nil,
  }
end

local function busy(id)
  local job = jobs[id]
  return job and (job.summary or job.translation) and true or false
end

local function write_atomic(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local temp = path .. ".tmp"
  if vim.fn.writefile(lines, temp) ~= 0 then
    error("cannot write " .. temp)
  end
  local ok, err = vim.uv.fs_rename(temp, path)
  if not ok then
    error(err)
  end
end

local function save(kind, e, text)
  local body = vim.split(text, "\n", { plain = true })
  local lines
  if kind == "summary" then
    lines = { "# " .. e.title:gsub("%s+", " "), "", e.url, (e.feed .. "  " .. e.published):gsub("%s+", " "), "" }
  else
    lines = M.read(e.id) or {}
    vim.list_extend(lines, { "", TRANSLATION_MARKER, "", "---", "", "## 번역", "" })
  end
  vim.list_extend(lines, body)
  write_atomic(M.path(e.id), lines)
  files[e.id] = nil
end

local function login_hint(message)
  if message:lower():find("log", 1, true) and message:lower():find("in", 1, true) then
    return ("%s (log in once: CLAUDE_CONFIG_DIR=%s claude)"):format(message, config().config_dir)
  end
  return message
end

-- ask(kind, source, cb(err, text)); same invocation as native-host/clip_host.mjs.
-- --tools '': the input is untrusted web text, so the model gets no tools.
local function ask(kind, source, cb)
  local cfg = config()
  local prompt_path = cfg.prompts[kind] or DEFAULT_PROMPTS[kind]
  if vim.fn.filereadable(prompt_path) ~= 1 then
    return cb("prompt not found: " .. prompt_path)
  end
  local cmd = vim.deepcopy(cfg.cmd)
  vim.list_extend(cmd, {
    "-p", "--model", cfg.models[kind],
    "--system-prompt", table.concat(vim.fn.readfile(prompt_path), "\n"),
    "--tools", "", "--no-session-persistence",
  })
  local handle
  local ok, result = pcall(vim.system, cmd, {
    text = true,
    stdin = source,
    cwd = vim.uv.os_tmpdir(),
    env = { CLAUDE_CONFIG_DIR = vim.fn.expand(cfg.config_dir) },
    timeout = cfg.timeout_ms[kind],
  }, function(res)
    vim.schedule(function()
      processes[handle] = nil
      if res.code == 124 then
        return cb("timed out")
      end
      local stdout = vim.trim(res.stdout or "")
      if res.code ~= 0 then
        local detail = vim.trim(res.stderr or "")
        return cb(login_hint(detail ~= "" and detail or (stdout ~= "" and stdout or ("exit " .. res.code))))
      end
      if stdout == "" then
        return cb("empty response")
      end
      cb(nil, stdout)
    end)
  end)
  if not ok then
    return cb(("cannot run %s: %s"):format(cfg.cmd[1], result))
  end
  handle = result
  processes[handle] = true
end

local function pump()
  while running < config().concurrency and #pending > 0 do
    local item = table.remove(pending, 1)
    local job = jobs[item.entry.id]
    running = running + 1
    job[item.kind] = "running"
    changed(item.entry.id)

    local function finish(err, text)
      running = running - 1
      job[item.kind] = nil
      if not err then
        local ok, save_err = pcall(save, item.kind, item.entry, text)
        err = not ok and tostring(save_err) or nil
      end
      if err then
        job.error, job.translate_next = err, nil
      elseif item.kind == "summary" and job.translate_next then
        job.translate_next = nil
        job.translation = "queued"
        table.insert(pending, { kind = "translation", entry = item.entry, load = item.load })
      end
      changed(item.entry.id)
      pump()
    end

    item.load(item.entry, function(err, source)
      if err then
        return finish(err)
      end
      ask(item.kind, source, finish)
    end)
  end
end

-- enqueue(kind, entry, load): load(entry, cb(err, source)) supplies the article text.
-- Returns false when there is nothing to do.
function M.enqueue(kind, e, load)
  local job = jobs[e.id] or {}
  jobs[e.id] = job
  local file = file_state(e.id)
  if kind == "summary" then
    if busy(e.id) or file.summary then
      return false
    end
  elseif file.translation or job.translation or job.translate_next then
    return false
  elseif busy(e.id) then
    job.translate_next = true
    return true
  elseif not file.summary then
    job.translate_next = true
    kind = "summary"
  end
  job.error = nil
  job[kind] = "queued"
  table.insert(pending, { kind = kind, entry = e, load = load })
  pump()
  changed(e.id)
  return true
end

-- remove(id): false while a job for this entry is active.
function M.remove(id)
  if busy(id) then
    return false
  end
  vim.fn.delete(M.path(id))
  jobs[id], files[id] = nil, nil
  changed(id)
  return true
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("folo_ai", {}),
  callback = function()
    for process in pairs(processes) do
      process:kill(15)
    end
  end,
})

return M

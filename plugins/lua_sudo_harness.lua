local gopherbot = require("gopherbot_v1")
local bot = gopherbot.Robot:new()
local task = gopherbot.task
local ret = gopherbot.ret
local log = gopherbot.log

local command = arg[1]

if command == "configure" then
  return "---\nCommands: []"
end

local function log_msg(level, message)
  bot:Log(level, "lua-sudo-harness: " .. tostring(message))
end

local function info(message)
  log_msg(log.Info, message)
end

local function warn(message)
  log_msg(log.Warn, message)
end

local function err(message)
  log_msg(log.Error, message)
end

local function trim(s)
  return tostring(s or ""):match("^%s*(.-)%s*$")
end

local function quote(s)
  s = tostring(s or "")
  return "'" .. s:gsub("'", "'\"'\"'") .. "'"
end

local function summarize(out)
  out = trim(out)
  if out == "" then
    return "<empty>"
  end
  if #out > 220 then
    return out:sub(1, 220) .. "...<truncated>"
  end
  return out
end

local function shell_capture(cmd, label)
  label = label or cmd
  info("shell start: " .. label)
  local marker = "__GBOT_STATUS__"
  local pipe, popen_err = io.popen(cmd .. " 2>&1; _gb_status=$?; printf '\\n" .. marker .. "%s' \"$_gb_status\"", "r")
  if not pipe then
    err("shell popen failed: " .. label .. ": " .. tostring(popen_err))
    return false, "", tostring(popen_err)
  end
  local out = pipe:read("*a") or ""
  pipe:close()
  local body, status = out:match("^(.*)\n" .. marker .. "(%d+)$")
  if not status then
    err("shell missing status: " .. label .. ": " .. summarize(out))
    return false, out, "missing status"
  end
  local ok = tonumber(status) == 0
  if ok then
    info("shell done: " .. label .. " status=" .. status .. " output=" .. summarize(body))
  else
    warn("shell failed: " .. label .. " status=" .. status .. " output=" .. summarize(body))
  end
  return ok, body or "", status
end

local function write_local(path, content)
  info("local write start: path=" .. tostring(path) .. " bytes=" .. tostring(#content))
  local f, open_err = io.open(path, "w")
  if not f then
    err("local write open failed: " .. tostring(open_err))
    return false, tostring(open_err)
  end
  f:write(content)
  f:close()
  info("local write done: path=" .. tostring(path))
  return true, ""
end

local function read_local(path)
  local f, open_err = io.open(path, "r")
  if not f then
    return nil, tostring(open_err)
  end
  local content = f:read("*a") or ""
  f:close()
  return content, nil
end

local function sudo_install_file(target_path, content, timeout_seconds)
  timeout_seconds = tonumber(timeout_seconds or 20) or 20
  info("sudo install probe start: target=" .. tostring(target_path) .. " bytes=" .. tostring(#content))

  local ok, tmp_path, status = shell_capture("mktemp /tmp/floyd-lua-sudo.XXXXXX", "mktemp")
  tmp_path = trim(tmp_path)
  if not ok or tmp_path == "" then
    return false, "mktemp status=" .. tostring(status)
  end

  local wrote, write_err = write_local(tmp_path, content)
  if not wrote then
    shell_capture("rm -f " .. quote(tmp_path), "cleanup temp")
    return false, write_err
  end

  shell_capture("chmod 0600 " .. quote(tmp_path), "chmod temp")
  ok, _, status = shell_capture(
    "timeout " .. tostring(timeout_seconds) .. "s sudo -n install -m 0600 -o root -g root " .. quote(tmp_path) .. " " .. quote(target_path),
    "sudo install root probe"
  )
  shell_capture("rm -f " .. quote(tmp_path), "cleanup temp")
  if not ok then
    return false, "install status=" .. tostring(status)
  end

  local stat_ok, stat_out, stat_status = shell_capture("timeout " .. tostring(timeout_seconds) .. "s sudo -n stat -c '%u:%g:%a' " .. quote(target_path), "sudo stat root probe")
  if not stat_ok then
    return false, "stat status=" .. tostring(stat_status)
  end

  local read_ok, read_out, read_status = shell_capture("timeout " .. tostring(timeout_seconds) .. "s sudo -n cat " .. quote(target_path), "sudo cat root probe")
  if not read_ok then
    return false, "cat status=" .. tostring(read_status)
  end
  if read_out ~= content then
    return false, "readback mismatch"
  end

  info("sudo install probe done: target=" .. tostring(target_path) .. " stat=" .. trim(stat_out))
  return true, trim(stat_out)
end

local function add_result(results, name, ok, detail)
  table.insert(results, name .. "=" .. (ok and "ok" or "fail") .. "(" .. tostring(detail or "") .. ")")
end

local function run_probe()
  info("probe start: user=" .. tostring(bot.user) .. " channel=" .. tostring(bot.channel))
  local cfg, cfg_ret = bot:GetTaskConfig()
  if cfg_ret ~= ret.Ok then
    err("config load failed: ret=" .. tostring(cfg_ret))
    bot:Say("Lua sudo harness configuration unavailable")
    return task.Fail
  end

  local local_path = cfg.LocalProbePath or "/tmp/floyd-lua-sudo-harness-local.txt"
  local root_path = cfg.RootProbePath or "/tmp/floyd-lua-sudo-harness-root.txt"
  local timeout_seconds = tonumber(cfg.CommandTimeoutSeconds or 20) or 20
  local content = "lua sudo harness ok\n"
  local results = {}

  local ok, out, status = shell_capture("id -u -n; id -u", "process identity")
  add_result(results, "process_identity", ok, trim(out):gsub("\n", "/"))

  ok, out, status = shell_capture("timeout " .. tostring(timeout_seconds) .. "s sudo -n id -u", "sudo identity")
  add_result(results, "sudo_identity", ok and trim(out) == "0", "status=" .. tostring(status) .. " out=" .. trim(out))

  ok = write_local(local_path, content)
  local read_back, read_err = read_local(local_path)
  add_result(results, "local_io", ok and read_back == content, read_err or "bytes=" .. tostring(#(read_back or "")))

  ok, out = sudo_install_file(root_path, content, timeout_seconds)
  add_result(results, "sudo_install", ok, out)

  shell_capture("rm -f " .. quote(local_path), "cleanup local probe")
  shell_capture("timeout " .. tostring(timeout_seconds) .. "s sudo -n rm -f " .. quote(root_path), "cleanup root probe")

  info("probe done: " .. table.concat(results, " | "))
  bot:Say("LUA_SUDO_PROBE " .. table.concat(results, " | "))
  return task.Normal
end

if command == "init" then
  return task.Normal
end

if command == "lua-sudo-probe" then
  return run_probe()
end

return task.Normal

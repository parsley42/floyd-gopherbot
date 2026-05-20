local gopherbot = require("gopherbot_v1")
local bot = gopherbot.Robot:new()
local ret = gopherbot.ret
local task = gopherbot.task

local command = arg[1]

if command == "configure" then
  return "---\nCommands: []"
end

local function say(message)
  bot:Say(message)
end

local function trim(s)
  return tostring(s or ""):match("^%s*(.-)%s*$")
end

local function shell_quote(s)
  s = tostring(s or "")
  return "'" .. s:gsub("'", "'\"'\"'") .. "'"
end

local function shell_capture(cmd)
  local marker = "__GBOT_STATUS__"
  local pipe, err = io.popen(cmd .. " 2>&1; _gb_status=$?; printf '\\n" .. marker .. "%s' \"$_gb_status\"", "r")
  if not pipe then
    return false, "", tostring(err)
  end
  local out = pipe:read("*a") or ""
  pipe:close()
  local body, status = out:match("^(.*)\n" .. marker .. "(%d+)$")
  if not status then
    return false, out, "missing status"
  end
  return tonumber(status) == 0, body or "", status
end

local function sudo_write_file(path, content)
  local cmd = "sudo -n sh -c " .. shell_quote("umask 077; cat > " .. shell_quote(path))
  local pipe, err = io.popen(cmd, "w")
  if not pipe then
    return false, tostring(err)
  end
  pipe:write(content)
  local ok, how, code = pipe:close()
  if ok == true or ok == 0 or (how == "exit" and code == 0) then
    return true, ""
  end
  return false, tostring(ok) .. "/" .. tostring(how) .. "/" .. tostring(code)
end

local function parse_ipv4(ip)
  local a, b, c, d = tostring(ip):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if not a or not b or not c or not d then
    return nil
  end
  if a > 255 or b > 255 or c > 255 or d > 255 then
    return nil
  end
  return a * 16777216 + b * 65536 + c * 256 + d
end

local function format_ipv4(n)
  local a = math.floor(n / 16777216) % 256
  local b = math.floor(n / 65536) % 256
  local c = math.floor(n / 256) % 256
  local d = n % 256
  return string.format("%d.%d.%d.%d", a, b, c, d)
end

local function split_cidr(cidr)
  local ip, prefix = tostring(cidr or ""):match("^([^/]+)/(%d+)$")
  if not ip then
    return nil, nil
  end
  prefix = tonumber(prefix)
  if not parse_ipv4(ip) or not prefix or prefix < 0 or prefix > 32 then
    return nil, nil
  end
  return ip, prefix
end

local function next_host_ip(cidr_or_host)
  local ip = tostring(cidr_or_host or ""):match("^([^/]+)") or ""
  local n = parse_ipv4(ip)
  if not n then
    return nil
  end
  return format_ipv4(n + 1) .. "/32"
end

local function is_global_ipv4(address)
  local ip = tostring(address or ""):match("^([^/]+)") or ""
  local n = parse_ipv4(ip)
  if not n then
    return false
  end
  local first = math.floor(n / 16777216) % 256
  local second = math.floor(n / 65536) % 256
  if first == 0 or first == 10 or first == 127 or first >= 224 then
    return false
  end
  if first == 100 and second >= 64 and second <= 127 then
    return false
  end
  if first == 169 and second == 254 then
    return false
  end
  if first == 172 and second >= 16 and second <= 31 then
    return false
  end
  if first == 192 and second == 168 then
    return false
  end
  return true
end

local function sorted_keys(tbl)
  local keys = {}
  for key in pairs(tbl or {}) do
    table.insert(keys, key)
  end
  table.sort(keys)
  return keys
end

local function load_config()
  local cfg, rv = bot:GetTaskConfig()
  if rv ~= ret.Ok then
    say("WireGuard plugin configuration is unavailable")
    return nil
  end
  cfg.ManageHost = cfg.ManageHost == true
  cfg.WireGuardConfigPath = cfg.WireGuardConfigPath or "/etc/wireguard/wg0.conf"
  cfg.InterfaceAddress = cfg.InterfaceAddress or "10.77.0.1/24"
  cfg.ListenPort = tonumber(cfg.ListenPort or 51820)
  cfg.PostUp = cfg.PostUp or "/etc/wireguard/start-nat.sh"
  cfg.PostDown = cfg.PostDown or "/etc/wireguard/stop-nat.sh"
  if not cfg.PrivateKey or cfg.PrivateKey == "" then
    say("WireGuard private key is not configured")
    return nil
  end
  if not split_cidr(cfg.InterfaceAddress) then
    say("WireGuard interface address is invalid")
    return nil
  end
  return cfg
end

local function checkout_state(rw)
  local state, rv = bot:CheckoutDatum("wg", rw)
  if rv ~= ret.Ok then
    say("Unable to load WireGuard state")
    return nil
  end
  state.datum = state.datum or {}
  state.datum.Latest_IP = state.datum.Latest_IP or ""
  state.datum.Users = state.datum.Users or {}
  return state
end

local function update_state(state)
  local rv = bot:UpdateDatum(state)
  if rv ~= ret.Ok then
    say("Unable to update WireGuard state")
    return false
  end
  return true
end

local function checkin_state(state)
  if state and state.token and state.token ~= "" then
    bot:CheckinDatum(state)
  end
end

local function gen_psk()
  local ok, out = shell_capture("wg genpsk")
  if not ok then
    return nil
  end
  return trim(out)
end

local function external_ip()
  local ok, http = pcall(require, "http")
  if not ok then
    return nil
  end
  local response, err = http.request("GET", "https://cloudflare.com/cdn-cgi/trace", { timeout = "5s" })
  if err or response.status_code ~= 200 then
    return nil
  end
  return (response.body or ""):match("\nip=([^\n]+)") or (response.body or ""):match("^ip=([^\n]+)")
end

local function render_config(cfg, state)
  local lines = {
    "[Interface]",
    "Address = " .. tostring(cfg.InterfaceAddress),
    "PrivateKey = " .. tostring(cfg.PrivateKey),
    "ListenPort = " .. tostring(cfg.ListenPort),
    "PostUp = " .. tostring(cfg.PostUp),
    "PostDown = " .. tostring(cfg.PostDown),
    "",
  }

  for _, user in ipairs(sorted_keys(state.datum.Users)) do
    local devices = state.datum.Users[user]
    for _, device in ipairs(sorted_keys(devices)) do
      local data = devices[device]
      table.insert(lines, "[Peer]")
      table.insert(lines, "# " .. user .. " | " .. device)
      table.insert(lines, "PublicKey = " .. tostring(data.PublicKey))
      table.insert(lines, "PreSharedKey = " .. tostring(data.PreSharedKey))
      table.insert(lines, "AllowedIPs = " .. tostring(data.AllowedIPs))
      table.insert(lines, "")
    end
  end

  return table.concat(lines, "\n")
end

local function apply_wireguard(cfg, state)
  if not cfg.ManageHost then
    return true
  end

  local ok, detail = sudo_write_file(cfg.WireGuardConfigPath, render_config(cfg, state))
  if not ok then
    say("Unable to write WireGuard configuration: " .. tostring(detail))
    return false
  end

  shell_capture("sudo -n systemctl enable wg-quick@wg0")
  ok, detail = shell_capture("sudo -n systemctl restart wg-quick@wg0")
  if not ok then
    say("Unable to restart WireGuard: " .. tostring(detail))
    return false
  end
  return true
end

local function add_device(cfg, state, device, public_key)
  local username = bot.user
  if not username or username == "" then
    say("Unable to determine the requesting user")
    return false
  end
  device = string.lower(device or "")
  if device == "" or not device:match("^[%.%w%-]+$") then
    say("Invalid device name")
    return false
  end
  if not public_key or not public_key:match("^[%.%w/%+=%-]+$") then
    say("Invalid public key")
    return false
  end

  state.datum.Users[username] = state.datum.Users[username] or {}
  if state.datum.Users[username][device] then
    checkin_state(state)
    say("Error: Device Already Added.")
    return false
  end

  local user_ip
  if state.datum.Latest_IP == "" then
    user_ip = next_host_ip(cfg.InterfaceAddress)
  else
    user_ip = next_host_ip(state.datum.Latest_IP)
  end
  if not user_ip then
    say("Unable to allocate a VPN address")
    return false
  end

  local psk = gen_psk()
  if not psk or psk == "" then
    say("Unable to generate a WireGuard pre-shared key")
    return false
  end

  state.datum.Latest_IP = user_ip
  state.datum.Users[username][device] = {
    PublicKey = public_key,
    PreSharedKey = psk,
    AllowedIPs = user_ip,
  }

  if not update_state(state) then
    return false
  end
  if not apply_wireguard(cfg, state) then
    return false
  end

  local ip = external_ip() or "<robot-public-ip>"
  say("VPN config data: Robot_IP = " .. ip .. ":" .. tostring(cfg.ListenPort) .. " | USER_IP = " .. user_ip .. " | PSK = " .. psk)
  return true
end

local function delete_user(cfg, state, username)
  username = string.lower(username or "")
  if state.datum.Users[username] then
    state.datum.Users[username] = nil
    if update_state(state) and apply_wireguard(cfg, state) then
      say("User '" .. username .. "' deleted successfully.")
    end
  else
    say("User '" .. username .. "' not found.")
  end
end

local function delete_device(cfg, state, device)
  local username = bot.user
  device = string.lower(device or "")
  if state.datum.Users[username] and state.datum.Users[username][device] then
    state.datum.Users[username][device] = nil
    if update_state(state) and apply_wireguard(cfg, state) then
      say("Device '" .. device .. "' deleted successfully.")
    end
  else
    say("Device '" .. device .. "' not found for user '" .. tostring(username) .. "'.")
  end
end

local function list_users(state)
  local rows = {}
  for _, username in ipairs(sorted_keys(state.datum.Users)) do
    table.insert(rows, username .. ": " .. table.concat(sorted_keys(state.datum.Users[username]), ", "))
  end
  if #rows == 0 then
    say("No Users Found.")
  else
    say("\n" .. table.concat(rows, "\n"))
  end
end

local function list_devices(state)
  local username = bot.user
  if state.datum.Users[username] then
    say("Device(s) for user '" .. username .. "': " .. table.concat(sorted_keys(state.datum.Users[username]), ", "))
  else
    say("No devices found for user '" .. tostring(username) .. "'")
  end
end

local function get_vpn(cfg, state, device)
  local username = bot.user
  device = string.lower(device or "")
  if not state.datum.Users[username] or not state.datum.Users[username][device] then
    say("Device '" .. device .. "' not found for user '" .. tostring(username) .. "'")
    return
  end
  local data = state.datum.Users[username][device]
  local ip = external_ip() or "<robot-public-ip>"
  say("VPN config data: Robot_IP = " .. ip .. ":" .. tostring(cfg.ListenPort) .. " | USER_IP = " .. data.AllowedIPs .. " | PSK = " .. data.PreSharedKey)
end

local function get_vpn_info(cfg)
  if not cfg.PublicKey or cfg.PublicKey == "" then
    say("WireGuard public key is not configured")
    return
  end
  local ip = external_ip() or "<robot-public-ip>"
  say("WireGuard VPN info:\nPublic key: " .. tostring(cfg.PublicKey) .. "\nEndpoint: " .. ip .. ":" .. tostring(cfg.ListenPort))
end

local function allow_ip(address)
  if not is_global_ipv4(address) then
    say("Invalid, unparseable, or non-public IP address")
    return
  end
  local ok, out = shell_capture("sudo -n iptables -L ALLOW_VPN -n")
  if not ok then
    say("Unable to inspect ALLOW_VPN firewall chain")
    return
  end
  for line in out:gmatch("[^\n]+") do
    if line:match("^ACCEPT") and line:find(address, 1, true) then
      say("IP already allowed")
      return
    end
  end
  ok = shell_capture("sudo -n iptables -A ALLOW_VPN -s " .. shell_quote(address) .. " -j ACCEPT")
  if ok then
    say("IP address added")
  else
    say("Unable to add IP address")
  end
end

local cfg = load_config()
if not cfg then
  return task.Fail
end

if command == "allow-ip" then
  allow_ip(arg[2])
  return task.Normal
end

if command == "get-vpn-info" then
  get_vpn_info(cfg)
  return task.Normal
end

local write_commands = {
  ["add-device"] = true,
  ["admin-delete-vpn-user"] = true,
  ["delete-device"] = true,
  ["clear-vpn"] = true,
}

local state = checkout_state(write_commands[command] == true)
if not state then
  return task.Fail
end

if command == "init" then
  apply_wireguard(cfg, state)
elseif command == "add-device" then
  add_device(cfg, state, arg[2], arg[3])
elseif command == "admin-list-vpn-users" then
  list_users(state)
elseif command == "admin-delete-vpn-user" then
  delete_user(cfg, state, arg[2])
elseif command == "list-vpn-devices" then
  list_devices(state)
elseif command == "delete-device" then
  delete_device(cfg, state, arg[2])
elseif command == "get-vpn" then
  get_vpn(cfg, state, arg[2])
elseif command == "clear-vpn" then
  state.datum.Users = {}
  state.datum.Latest_IP = ""
  if update_state(state) and apply_wireguard(cfg, state) then
    if cfg.ManageHost then
      shell_capture("sudo -n iptables -F ALLOW_VPN")
    end
    say("Cleared all VPN users and devices, and emptied the ALLOW_VPN chain")
  end
end

return task.Normal

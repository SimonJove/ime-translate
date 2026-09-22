-- Process-wide singleton: config, the API keys and (feature 003) the active
-- backend slot. **Never session state** -- that lives in session.lua, on the
-- Context. librime-lua gives every component one shared Lua state, so
-- module-level session state crosses wires. The active slot is not session
-- state: it must be the same in every input box, because the network it
-- answers to is the machine's (design §5.6, §6.1).
local config = require("ime_translate.config")
local json = require("ime_translate.json")

local shared = { settings = nil, warnings = nil, api_key = nil, cloud_key = nil,
                 active = "local", loaded = false }

local HOME = os.getenv("HOME") or ""
-- Replaced only by the tests.
shared.config_path = HOME .. "/Library/Rime/ime_translate.yaml"
shared.active_path = HOME .. "/Library/Rime/ime_translate.active"

-- Read an API key from the macOS Keychain. Called once per slot at startup,
-- and the key cached in memory. Never read a secret from ~/Library/Rime/: that
-- directory is rescanned wholesale on "Redeploy" and many users push it to
-- GitHub as config sync.
function shared.read_key(account)
  if not account or account == "" then return nil end
  -- Escaping goes through json.shq (POSIX single quotes). Never use
  -- string.format("%q", ...): that is Lua literal escaping, it produces double
  -- quotes, and $() and backticks still expand inside them in a shell.
  local cmd = "security find-generic-password -s ime-translate -a "
              .. json.shq(account) .. " -w 2>/dev/null"
  local f = io.popen(cmd, "r")
  if not f then return nil end
  -- [ \t\r\n], not %s: %s follows the C locale's isspace() (see json.lua)
  local key = (f:read("*a") or ""):gsub("[ \t\r\n]+$", "")
  f:close()
  return key ~= "" and key or nil
end

-- Feature 003: the remembered slot. Anything but "cloud", or "cloud" with no
-- cloud slot, is local.
local function read_active(has_cloud)
  local f = io.open(shared.active_path, "r")
  if not f then return "local" end
  local word = (f:read("*l") or ""):gsub("[ \t\r]+$", "")
  f:close()
  return (word == "cloud" and has_cloud) and "cloud" or "local"
end

local function write_active(name)
  local f = io.open(shared.active_path, "w")
  if not f then return false end
  local wrote = f:write(name, "\n")
  local closed = f:close()
  return wrote ~= nil and closed == true
end

function shared.ensure()
  if not shared.loaded then
    local f = io.open(shared.config_path, "r")
    -- config.load returns (settings, warnings); capture both. Dropping warnings
    -- means a user who mistypes config never sees any hint of it.
    shared.settings, shared.warnings =
      config.load(function() return f and f:read("*a") or nil end)
    if f then f:close() end
    shared.api_key = shared.read_key(shared.settings.api_key_account)
    local cloud = shared.settings.cloud
    shared.cloud_key = cloud and shared.read_key(cloud.api_key_account) or nil
    shared.active = read_active(cloud ~= nil)
    shared.loaded = true
  end
  return shared
end

-- The active slot's settings and Keychain key.
function shared.current()
  if shared.active == "cloud" and shared.settings.cloud then
    return shared.settings.cloud, shared.cloud_key
  end
  return shared.settings, shared.api_key
end

-- Ctrl+Shift+B (design §5.6). Returns the slot now active and whether it was
-- remembered; nil when there is no cloud slot, and local stays. A failed write
-- still switches, for this Lua state.
function shared.switch()
  if not shared.settings.cloud then
    shared.active = "local"
    return nil
  end
  shared.active = shared.active == "cloud" and "local" or "cloud"
  return shared.active, write_active(shared.active)
end

return shared

-- Process-wide read-only singleton: config and the API key. **Never session
-- state** -- that lives in session.lua, on the Context. librime-lua gives every
-- component one shared Lua state, so module-level session state crosses wires.
local config = require("ime_translate.config")
local json = require("ime_translate.json")

local shared = { settings = nil, warnings = nil, api_key = nil, loaded = false }

-- Read the API key from the macOS Keychain once at startup and cache it in
-- memory. Never read a secret from ~/Library/Rime/: that directory is rescanned
-- wholesale on "Redeploy" and many users push it to GitHub as config sync.
local function read_key(account)
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

function shared.ensure()
  if not shared.loaded then
    local path = os.getenv("HOME") .. "/Library/Rime/ime_translate.yaml"
    local f = io.open(path, "r")
    -- config.load returns (settings, warnings); capture both. Dropping warnings
    -- means a user who mistypes config never sees any hint of it.
    shared.settings, shared.warnings =
      config.load(function() return f and f:read("*a") or nil end)
    if f then f:close() end
    shared.api_key = read_key(shared.settings.api_key_account)
    shared.loaded = true
  end
  return shared
end

return shared

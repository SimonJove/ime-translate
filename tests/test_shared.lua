package.path = package.path .. ";rime/lua/?.lua"
-- Feature 003 (design §5.6): the active slot, process-wide, remembered in a
-- file. Both paths are temporary files and the Keychain read is stubbed, so
-- nothing here touches ~/Library or runs security.
local shared = require("ime_translate_shared")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

local CFG, ACT = os.tmpname(), os.tmpname()
shared.config_path, shared.active_path = CFG, ACT
local reads = {}
shared.read_key = function(account)
  reads[#reads + 1] = account
  return account ~= "" and ("key-for-" .. account) or nil
end
local function write(path, text)
  local f = assert(io.open(path, "w")); f:write(text); f:close()
end
local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s
end
-- A new Lua state: what a redeploy gives (upstream F28)
local function fresh(config_text, active_text)
  write(CFG, config_text)
  if active_text then write(ACT, active_text) else os.remove(ACT) end
  shared.loaded, reads = false, {}
  return shared.ensure()
end
local CLOUD = "api_key_account: local-acct\nallow_remote: true\ncloud_backend: openai\n" ..
              "cloud_base_url: https://open.bigmodel.cn/api/paas/v4\ncloud_api_key_account: cloud-acct\n"

-- no active file: local
local S = fresh(CLOUD, nil)
eq(S.active, "local", "no active file starts on local")
local s, key, name = S.current()
eq(s, S.settings, "local: the local settings")
eq(name, "local", "local: named local")
eq(key, "key-for-local-acct", "local: the local key")
eq(#reads, 2, "both keys are read at ensure")
eq(reads[2], "cloud-acct", "the cloud key is read under its own account")
eq(S.cloud_key, "key-for-cloud-acct", "the cloud key is kept")
-- Feature 005 (backend.md §8.3): one translation cache per Lua state
assert(S.cache and S.cache.get and S.cache.put, "ensure creates the cache")
local the_cache = S.cache
S.cache:put("local", "x", "y")
eq(shared.ensure().cache, the_cache, "a second ensure keeps the same cache")
eq(shared.ensure().cache:get("local", "x"), "y", "and what it holds")

-- the switch goes to cloud; current() follows, and the file says so
local now, remembered = S.switch()
eq(now, "cloud", "the switch goes to cloud")
eq(remembered, true, "the switch is remembered")
eq(read(ACT), "cloud\n", "the active file says cloud")
s, key, name = S.current()
eq(s, S.settings.cloud, "cloud: the cloud settings")
eq(name, "cloud", "cloud: named cloud")
eq(key, "key-for-cloud-acct", "cloud: the cloud key")
-- and back
now = S.switch()
eq(now, "local", "the second switch goes back to local")
eq(read(ACT), "local\n", "the active file says local")
eq(S.current(), S.settings, "local again")

-- ensure reads once per Lua state: a switch rereads nothing
local before = #reads
S.switch(); S.ensure(); S.switch()
eq(#reads, before, "no Keychain read after ensure")

-- a new Lua state reads the remembered slot
S = fresh(CLOUD, "cloud\n")
eq(S.active, "cloud", "cloud is remembered across a reload")
eq(S.current(), S.settings.cloud, "and used")
eq(fresh(CLOUD, "cloud  \r\n").active, "cloud", "trailing whitespace is fine")
eq(fresh(CLOUD, "Cloud\n").active, "local", "Cloud is not cloud")
eq(fresh(CLOUD, "").active, "local", "an empty file is local")
eq(fresh(CLOUD, "garbage\n").active, "local", "anything else is local")

-- cloud remembered but no cloud slot: local, and the switch has nowhere to go
S = fresh("api_key_account: local-acct\n", "cloud\n")
eq(S.active, "local", "cloud with no cloud slot starts on local")
eq(S.current(), S.settings, "and uses the local slot")
eq(select(3, S.current()), "local", "named local")
S.active = "cloud"  -- even forced, no cloud slot means local
eq(select(3, S.current()), "local", "a forced cloud with no slot is still local")
S.active = "local"
eq(#reads, 1, "no cloud slot: only the local key is read")
eq(S.cloud_key, nil, "no cloud key")
now, remembered = S.switch()
eq(now, nil, "no cloud slot: the switch returns nil")
eq(S.active, "local", "and stays on local")
eq(read(ACT), "cloud\n", "a switch with no cloud slot writes nothing")
-- Task 3 review, round 1, yellow: the file above already said cloud, so a
-- write of cloud would not show. With no file, any write would.
os.remove(ACT)
S.switch()
eq(read(ACT), nil, "a switch with no cloud slot creates no file")

-- a write that fails still switches, for this Lua state
S = fresh(CLOUD, nil)
shared.active_path = "/nonexistent-ime-translate-dir/active"
now, remembered = S.switch()
eq(now, "cloud", "a failed write still switches")
eq(remembered, false, "and says it was not remembered")
eq(S.current(), S.settings.cloud, "the switch holds in memory")
shared.active_path = ACT
-- green: the open works but the flush at close fails, as on a full disk
S = fresh(CLOUD, nil)
local real_open = io.open
io.open = function(path, mode)
  if path == ACT and mode == "w" then
    return { write = function(self) return self end,
             close = function() return nil, "No space left on device", 28 end }
  end
  return real_open(path, mode)
end
now, remembered = S.switch()
io.open = real_open
eq(now, "cloud", "a failed close still switches")
eq(remembered, false, "and is not remembered")

os.remove(CFG); os.remove(ACT)
print(("test_shared: %d assertions OK"):format(n))

# Task 3: The active slot and the cloud marker (TDD)

**Files:**
- Modify: `rime/lua/ime_translate_shared.lua`
- Modify: `rime/lua/ime_translate/session.lua` (`set_result`, `set_error`,
  `clear`, `prompt`)
- Create: `tests/test_shared.lua`
- Test: `tests/test_session.lua` (append before the final `print`)

**Interfaces:**
- Consumes: `settings.cloud` (Task 1).
- Produces, for Task 4:
  - `shared.active`: `"local"` or `"cloud"`, process-wide.
  - `shared.current()` returns `(settings, api_key)` for the active slot.
  - `shared.switch()` returns `(now, remembered)`. `now` is the slot active
    after the switch, or `nil` when there is no cloud slot, in which case local
    stays. `remembered` is whether the file write worked.
  - `shared.cloud_key`: the cloud slot's Keychain key, or `nil`.
  - `shared.config_path`, `shared.active_path` and `shared.read_key` can be
    replaced, and only the tests replace them.
  - `session.set_result(ctx, draft, text, cloud)` and
    `session.set_error(ctx, draft, code, cloud)`. `cloud` is true for an
    answer from a non-loopback `base_url`. Left out, it is false, so every
    existing caller is unchanged.
  - `session.prompt(ctx)` gives `  ☁ text` for a cloud result and
    `  ☁ ✗ reason` for a cloud error.

Design §5.6, "One choice for the whole process" and "Remembered", and §6.4's
table. The active slot passes §6.1's test for module state: it must be the same
in every input box.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_shared.lua`:

```lua
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
local s, key = S.current()
eq(s, S.settings, "local: the local settings")
eq(key, "key-for-local-acct", "local: the local key")
eq(#reads, 2, "both keys are read at ensure")
eq(reads[2], "cloud-acct", "the cloud key is read under its own account")
eq(S.cloud_key, "key-for-cloud-acct", "the cloud key is kept")

-- the switch goes to cloud; current() follows, and the file says so
local now, remembered = S.switch()
eq(now, "cloud", "the switch goes to cloud")
eq(remembered, true, "the switch is remembered")
eq(read(ACT), "cloud\n", "the active file says cloud")
s, key = S.current()
eq(s, S.settings.cloud, "cloud: the cloud settings")
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
eq(#reads, 1, "no cloud slot: only the local key is read")
eq(S.cloud_key, nil, "no cloud key")
now, remembered = S.switch()
eq(now, nil, "no cloud slot: the switch returns nil")
eq(S.active, "local", "and stays on local")
eq(read(ACT), "cloud\n", "a switch with no cloud slot writes nothing")

-- a write that fails still switches, for this Lua state
S = fresh(CLOUD, nil)
shared.active_path = "/nonexistent-ime-translate-dir/active"
now, remembered = S.switch()
eq(now, "cloud", "a failed write still switches")
eq(remembered, false, "and says it was not remembered")
eq(S.current(), S.settings.cloud, "the switch holds in memory")
shared.active_path = ACT

os.remove(CFG); os.remove(ACT)
print(("test_shared: %d assertions OK"):format(n))
```

Append to `tests/test_session.lua`, just before its final `print(...)`:

```lua
---------- feature 003 (design §5.6, §6.4): the cloud marker ----------
local m = fake_ctx("今天")
session.set_result(m, "今天", "Today", true)
eq(session.prompt(m), "  ☁ Today", "a cloud result is marked")
session.set_result(m, "今天", "Today", false)
eq(session.prompt(m), "  -> Today", "a local result is not")
session.set_result(m, "今天", "Today")
eq(session.prompt(m), "  -> Today", "left out, cloud is false")
session.set_error(m, "今天", "timeout", true)
eq(session.prompt(m), "  ☁ ✗ 翻译超时", "a cloud error is marked")
session.set_error(m, "今天", "timeout")
eq(session.prompt(m), "  ✗ 翻译超时", "a local error is not")
session.set_result(m, "今天", "Today", true)
session.clear(m)
eq(m.props["ime_translate.cloud"], "", "clear drops the mark")
eq(session.prompt(m), "", "idle shows nothing")
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `lua tests/test_shared.lua; lua tests/test_session.lua`
Expected: `test_shared` fails at #1 or #2. `shared.ensure` still reads
`~/Library/Rime/ime_translate.yaml` and has no `active`, so the first `eq` or
`S.current` fails. `test_session` fails at `a cloud result is marked`: got
`  -> Today`.

- [ ] **Step 3: Implement `ime_translate_shared.lua`**

Replace the module with:

```lua
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
```

- [ ] **Step 4: Implement the marker in `session.lua`**

Below `K_SHIFT`:

```lua
-- Feature 003 (design §5.6): "1" when the result or error on screen came from
-- a non-loopback base_url
local K_CLOUD = "ime_translate.cloud"
```

`set_result` and `set_error` take a fourth argument and store it; `clear`
drops it:

```lua
function M.set_result(ctx, draft, text, cloud)
  ctx:set_property(K_DRAFT, draft)
  ctx:set_property(K_TEXT, text)
  ctx:set_property(K_CODE, "")
  ctx:set_property(K_CLOUD, cloud and "1" or "")
  ctx:set_property(K_PHASE, state.RESULT)
end

function M.set_error(ctx, draft, code, cloud)
  ctx:set_property(K_DRAFT, draft)
  ctx:set_property(K_TEXT, "")
  ctx:set_property(K_CODE, code)
  ctx:set_property(K_CLOUD, cloud and "1" or "")
  ctx:set_property(K_PHASE, state.ERROR)
end

function M.clear(ctx)
  ctx:set_property(K_PHASE, state.IDLE)
  ctx:set_property(K_TEXT, "")
  ctx:set_property(K_CODE, "")
  ctx:set_property(K_DRAFT, "")
  ctx:set_property(K_CLOUD, "")
end
```

and the prompt:

```lua
-- The display (design §6.4): what the processor writes into the last
-- segment's prompt. "  -> " is the form spike S11 measured in the preedit.
-- Feature 003: a cloud answer shows "☁" instead, the explicit marker design
-- §7.2 asks for.
function M.prompt(ctx)
  local p = M.phase(ctx)
  local cloud = ctx:get_property(K_CLOUD) == "1"
  if p == state.RESULT then return (cloud and "  ☁ " or "  -> ") .. M.text(ctx) end
  if p == state.ERROR then
    return "  " .. (cloud and "☁ " or "") .. state.error_message(M.code(ctx))
  end
  return ""
end
```

- [ ] **Step 5: Run them and confirm they pass**

Run: `lua tests/test_shared.lua && lua tests/test_session.lua && scripts/run_tests.sh`
Expected: `test_shared: … assertions OK`, `test_session: … assertions OK`,
and every file PASS. `test_glue_load` still finds `shared` lazy:
`loaded == false` and no settings before `ensure()`.

- [ ] **Step 6: Commit**

```bash
git add rime/lua/ime_translate_shared.lua rime/lua/ime_translate/session.lua \
        tests/test_shared.lua tests/test_session.lua
git commit -m "feat: a process-wide active backend slot and a cloud marker"
```

# Task 9: Rime glue layer (shared / processor)

**Files:**
- Create: `rime/lua/ime_translate_shared.lua`,
  `rime/lua/ime_translate_processor.lua`
- Test: `tests/test_glue_load.lua`

**Interfaces:**
- Consumes: `session.*` (Task 7), `decide.decide` (Task 8),
  `backend.translate/real_runner` (Task 6), `config.load` (Task 5),
  `session.prompt` (Task 7)
- Produces: the rime component module name `ime_translate_processor`, plus the
  process-wide read-only singleton `ime_translate_shared` (`.settings`
  `.warnings` `.api_key` `.loaded`)

> **Decision D1 (2026-09-21) reshaped this task.** The translation and the `✗`
> reason are shown in the last segment's `prompt`, written by the processor
> (design §6.4); there is no translator and no filter. Spike S11 measured the
> candidate display failing in both states and the prompt closing the loop in
> both. Invalidation is checked in two places, not three (design §6.2).

> **Read the spike report's "constants later tasks need" section before writing
> anything**: the real values of `kNoop` / `kAccepted`, and whether
> `key.release` is a method or a field. The code below assumes
> `kAccepted=1, kNoop=2` and `key:release()`; if the report says otherwise,
> follow the report.

- [ ] **Step 1: Write the load smoke test**

`tests/test_glue_load.lua`:

```lua
package.path = package.path .. ";rime/lua/?.lua"
-- The glue modules do only require/return at the top level and touch no rime
-- global, so they must load headless.
local names = { "ime_translate_shared", "ime_translate_processor" }
for _, name in ipairs(names) do
  local ok, m = pcall(require, name)
  assert(ok, ("fail to load %s: %s"):format(name, tostring(m)))
  assert(type(m) == "function" or type(m) == "table",
         name .. " must export func/table")
end
-- shared must not read files or spawn subprocesses at load time
local shared = require("ime_translate_shared")
assert(shared.loaded == false, "shared must be lazy: loaded=false before ensure()")
assert(shared.settings == nil, "shared must not read config at load time")
-- session state must never appear on the module singleton
assert(shared.fsm == nil, "no fsm on the module singleton")
assert(shared.phase == nil, "no phase on the module singleton")
-- D1: nothing but the processor is a rime component
for _, gone in ipairs({ "ime_translate_translator", "ime_translate_filter" }) do
  assert(not pcall(require, gone), gone .. " must not exist (decision D1)")
end
print("test_glue_load: 2 modules OK, shared is lazy and stateless")
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `lua tests/test_glue_load.lua`
Expected: FAIL (modules do not exist)

- [ ] **Step 3: Implement shared**

`rime/lua/ime_translate_shared.lua`:

```lua
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
```

- [ ] **Step 4: Implement the processor**

`rime/lua/ime_translate_processor.lua`:

```lua
-- Thin glue: read the context, call the pure decide function, execute the
-- action.
-- **This file is the only place in the project allowed to call
-- engine:commit_text().**
local shared = require("ime_translate_shared")
local session = require("ime_translate.session")
local decide = require("ime_translate.decide")
local backend = require("ime_translate.backend")

local kAccepted, kNoop = 1, 2 -- confirmed by spike Task 1 Step 3; follow the report if it differs

local function log(S, msg)
  if S.settings and S.settings.debug_log then
    local f = io.open(os.getenv("HOME") .. "/Library/Logs/ime_translate.log", "a")
    if f then f:write(os.date("%m-%d %H:%M:%S "), msg, "\n"); f:close() end
  end
end

-- The display is the last segment's prompt (design §6.4, decision D1): shown in
-- the preedit, never read by get_commit_text(), never committed. A non-empty
-- draft means a non-empty composition, so back() is a segment.
local function show(ctx, draft)
  if draft ~= "" then ctx.composition:back().prompt = session.prompt(ctx) end
end

local function processor(key, env)
  local S = shared.ensure()
  local ctx = env.engine.context

  -- On the first call, write any config warnings to the log
  if S.warnings and #S.warnings > 0 then
    for _, w in ipairs(S.warnings) do log(S, "config: " .. w) end
    S.warnings = {}
  end

  local draft = session.draft(ctx)

  -- Invalidation check number two (design §6.2): the draft changed while phase
  -- is still result/error -- a mouse click on a candidate, or any edit path we
  -- failed to anticipate. Every Enter passes here first, so a stale translation
  -- is never committed. The prompt goes with the phase.
  if session.stale(ctx) then
    session.clear(ctx)
    show(ctx, draft)
  end

  -- modifier goes in raw: decide drops Lock and every bit it does not read
  -- (R15, Task 8). release is a method on the KeyEvent, not a field.
  local k = { keycode = key.keycode, modifier = key.modifier, release = key:release() }
  local action = decide.decide(k, session.phase(ctx), draft == "")

  if action.type == "translate" then
    -- Synchronous block. settings.timeout_ms is the worst-case freeze here.
    local ok, out = backend.translate(S.settings, draft, backend.real_runner, S.api_key)
    if ok then session.set_result(ctx, draft, out)
    else session.set_error(ctx, draft, out) end
    -- No refresh_non_confirmed_composition(): the measured path (S11) wrote the
    -- prompt and returned, and a refresh may rebuild the segment holding it.
    show(ctx, draft)
    log(S, ("translate %q -> %s"):format(draft, ok and out or ("ERR " .. out)))
    return kAccepted

  elseif action.type == "commit_translation" then
    -- Never eat text: commit first, clear second. Context properties survive
    -- ctx:clear(), so they must be cleared explicitly; ctx:clear() removes the
    -- segment and its prompt with it.
    env.engine:commit_text(session.text(ctx))
    session.clear(ctx)
    ctx:clear()
    log(S, "commit translation")
    return kAccepted

  elseif action.type == "commit_draft" then
    env.engine:commit_text(draft)
    session.clear(ctx)
    ctx:clear()
    log(S, "commit draft")
    return kAccepted

  elseif action.type == "clear_display" then
    -- Esc in result/error: drop the prompt, keep the draft. Passed on, the
    -- native Esc wipes the whole draft (S11 row 5b).
    session.clear(ctx)
    show(ctx, draft)
    return kAccepted

  elseif action.type == "invalidate_and_pass" then
    session.clear(ctx)
    show(ctx, draft)
    return kNoop
  end

  return kNoop
end

return processor
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `lua tests/test_glue_load.lua && scripts/run_tests.sh`
Expected: everything PASS

- [ ] **Step 6: Commit**

```bash
git add rime/lua/ime_translate_shared.lua rime/lua/ime_translate_processor.lua \
        tests/test_glue_load.lua
git commit -m "feat: rime glue layer with the processor as sole commit owner"
```

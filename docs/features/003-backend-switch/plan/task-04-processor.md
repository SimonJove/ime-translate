# Task 4: The processor switches, and translates with the active slot (TDD)

**Files:**
- Modify: `rime/lua/ime_translate_processor.lua`
- Test: `tests/test_processor.lua` (append before the final `print`)

**Interfaces:**
- Consumes:
  - `decide` → `switch_backend` (Task 2)
  - `shared.current()`, `shared.switch()`, `shared.active` (Task 3)
  - `session.set_result/set_error(…, cloud)` (Task 3)
  - `config.is_loopback` (001)
- Produces: the behaviour of design §5.6. Task 5 declares the three notice
  switches the processor turns on and off:
  - `ime_translate_notice_local`
  - `ime_translate_notice_cloud`
  - `ime_translate_notice_no_cloud`

**The switch branch.**
- The prompt goes as for Esc (`session.clear`, then `show`); the draft stays.
  Nothing is committed and nothing is cleared.
- Then `shared.switch()`, then the matching notice switch is turned on and
  off. `set_option` notifies either way (F29), and only the on state has a
  label.
- Each call refreshes an open segment, as any option change does (F20); the
  input is untouched.

**The translate branch** uses `shared.current()`. The marker is decided by
`config.is_loopback(settings.base_url)`: the URL decides, not the slot's name.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_processor.lua`, just before its final `print(...)`:

```lua
---------- feature 003 (design §5.6): Ctrl+Shift+B and the active slot ----------
local CTRL, B = 0x4, 0x42
-- A switch writes the active file: never the real one under ~/Library
local ACTIVE = os.tmpname()
shared.active_path = ACTIVE
local function slurp(path)
  local f = io.open(path, "r"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local local_settings = shared.settings
local cloud_settings = config.load(function()
  return "allow_remote: true\ncloud_backend: openai\ncloud_base_url: https://api.example.com/v1\n"
end).cloud
assert(cloud_settings, "the cloud fixture loads")

-- no cloud slot: the switch stays local and says so
env, ctx, seg = fake("今天有点累")
eq(press(env, B, CTRL | SHIFT), kAccepted, "ctrl+shift+B is taken")
eq(trace(ctx), "ime_translate_notice_no_cloud=true,ime_translate_notice_no_cloud=false",
   "no cloud slot: the no-cloud notice, on then off")
eq(shared.active, "local", "no cloud slot: still local")
eq(#env.committed, 0, "the switch commits nothing")
eq(ctx._text, "今天有点累", "the draft is intact")

-- with a cloud slot: translate locally, switch, translate the same draft again
shared.settings.cloud, shared.cloud_key = cloud_settings, "cloud-sentinel"
env, ctx, seg = fake("今天有点累")
answer, calls = { true, "I'm a little tired today" }, {}
press(env, RET)
eq(args.settings, local_settings, "local: the local settings")
eq(args.key, "k-sentinel", "local: the local key")
eq(seg.prompt, "  -> I'm a little tired today", "a loopback translation is unmarked")
eq(press(env, B, CTRL | SHIFT), kAccepted, "the switch is taken in result")
eq(seg.prompt, "", "the translation on screen is voided")
eq(ctx:get_property("ime_translate.phase"), "idle", "back to idle")
eq(shared.active, "cloud", "switched to cloud")
eq(trace(ctx), "ime_translate_notice_cloud=true,ime_translate_notice_cloud=false",
   "the cloud notice, on then off")
eq(slurp(ACTIVE), "cloud\n", "the switch is remembered")
eq(#env.committed, 0, "nothing committed by the switch")
eq(ctx._text, "今天有点累", "the draft is intact after the switch")
answer, calls = { true, "A bit tired today" }, {}
eq(press(env, RET), kAccepted, "enter translates again")
eq(calls[1], "今天有点累", "the same draft")
eq(args.settings, cloud_settings, "with the cloud settings")
eq(args.key, "cloud-sentinel", "and the cloud key")
eq(seg.prompt, "  ☁ A bit tired today", "a cloud translation is marked")
eq(press(env, RET), kAccepted, "enter commits it")
eq(env.committed[1], "A bit tired today", "the cloud translation is committed")

-- a cloud error is marked, and Enter still commits the Chinese
env, ctx, seg = fake("今天")
answer = { false, "timeout" }
press(env, RET)
eq(seg.prompt, "  ☁ ✗ 翻译超时", "a cloud error is marked")
press(env, RET)
eq(env.committed[1], "今天", "the error fallback commits the draft")

-- the switch with no draft: taken, and back to local
env, ctx, seg = fake("")
eq(press(env, B, CTRL | SHIFT), kAccepted, "the switch with no draft is taken")
eq(shared.active, "local", "back to local")
eq(trace(ctx), "ime_translate_notice_local=true,ime_translate_notice_local=false",
   "the local notice")
eq(slurp(ACTIVE), "local\n", "local is remembered")
eq(#env.committed, 0, "nothing committed with no draft")

-- the release of the hotkey is not acted on
env, ctx, seg = fake("今天")
eq(processor(key(B, CTRL | SHIFT, true), env), kNoop, "the release passes")
eq(shared.active, "local", "the release switches nothing")

-- the URL decides the marker: a local slot pointed at a cloud is marked
shared.settings = config.load(function()
  return "allow_remote: true\nbackend: openai\nbase_url: https://api.example.com/v1\n"
end)
env, ctx, seg = fake("今天")
answer = { true, "Today" }
press(env, RET)
eq(seg.prompt, "  ☁ Today", "a remote URL in the local slot is marked")

shared.settings, local_settings.cloud, shared.cloud_key = local_settings, nil, nil
shared.active = "local"
os.remove(ACTIVE)
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `lua tests/test_processor.lua`
Expected: FAIL at `ctrl+shift+B is taken`: got 2 (kNoop). The processor has no
`switch_backend` branch yet.

- [ ] **Step 3: Implement**

In `rime/lua/ime_translate_processor.lua`, add to the requires:

```lua
local config = require("ime_translate.config")
```

and below `kAccepted, kNoop`:

```lua
-- Feature 003 (design §5.6): the notice switches the schema declares, one per
-- outcome of a switch. Squirrel shows the label of an option turned on; each
-- off label is empty, which keeps them out of the switcher menu and makes
-- turning one off show nothing (upstream F29).
local NOTICE = { ["local"] = "ime_translate_notice_local",
                 cloud = "ime_translate_notice_cloud",
                 none = "ime_translate_notice_no_cloud" }
```

The translate branch takes the active slot, and marks a cloud answer:

```lua
  if action.type == "translate" then
    -- Synchronous block. The active slot's timeout_ms is the worst-case freeze
    -- here. The slot is process-wide (design §5.6).
    local settings, api_key = S.current()
    local ok, out = backend.translate(settings, draft, backend.real_runner, api_key)
    -- The §7.2 cloud marker: decided by the URL, not by the slot's name
    local cloud = not config.is_loopback(settings.base_url)
    if ok then session.set_result(ctx, draft, out, cloud)
    else session.set_error(ctx, draft, out, cloud) end
    -- No refresh_non_confirmed_composition(): the measured path (S11) wrote the
    -- prompt and returned, and a refresh may rebuild the segment holding it.
    show(ctx, draft)
    log(S, ("translate [%s] %q -> %s"):format(S.active, draft, ok and out or ("ERR " .. out)))
    return kAccepted
```

A new branch, before `elseif action.type == "invalidate_and_pass"`:

```lua
  elseif action.type == "switch_backend" then
    -- Design §5.6: a translation on screen is voided first, as by Esc: the
    -- prompt goes, the draft stays, and the next Enter translates with the
    -- other backend. Nothing is committed or cleared.
    session.clear(ctx)
    show(ctx, draft)
    local now, remembered = S.switch()
    -- On, then off: set_option notifies either way, and only the on state has
    -- a label (F29). Each call refreshes an open segment, as any option change
    -- does (F20); the input is untouched.
    local notice = NOTICE[now or "none"]
    ctx:set_option(notice, true)
    ctx:set_option(notice, false)
    log(S, "switch backend: " .. (now or "no cloud slot")
           .. (remembered == false and ", not remembered" or ""))
    return kAccepted
```

- [ ] **Step 4: Run it and confirm it passes**

Run: `lua tests/test_processor.lua && scripts/run_tests.sh`
Expected: `test_processor: … assertions OK`, and every file PASS.

- [ ] **Step 5: Commit**

```bash
git add rime/lua/ime_translate_processor.lua tests/test_processor.lua
git commit -m "feat: Ctrl+Shift+B switches the translation backend"
```

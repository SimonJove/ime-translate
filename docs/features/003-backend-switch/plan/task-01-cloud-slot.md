# Task 1: The cloud slot in the config (TDD)

**Files:**
- Modify: `rime/lua/ime_translate/config.lua` (the key routing in the parse
  loop, the checks after it)
- Test: `tests/test_config.lua` (append before the final `print`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `config.load(read_fn)` returns `(settings, warnings)` as before,
  and `settings.cloud` is either `nil` or a complete settings table for the
  cloud slot: every key `settings` has, except `cloud`. `backend.translate`
  takes it unchanged. Task 3 reads `settings.cloud`.

Design: [backend.md §9](../../../design/backend.md), "Two backend slots".
- The slot keys are `backend`, `base_url`, `model`, `prompt`, `timeout_ms`,
  `temperature`, `max_tokens` and `api_key_account`. Under `cloud_` they
  belong to the cloud slot. `allow_remote`, `max_chars` and `debug_log` are
  shared.
- An unset cloud key takes the default, not the local slot's value.
- A cloud slot that fails the adapter or trust check is dropped, with a
  warning. A `cloud_timeout_ms` out of range resets to the default.
- `cloud_` keys with no `cloud_backend` warn once and make no slot. A shared
  key under the prefix (`cloud_allow_remote`) is an unknown key.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_config.lua`, just before its final `print(...)`:

```lua
---------- feature 003 (backend.md §9): the cloud slot ----------
eq(load(nil).cloud, nil, "no cloud_ keys: no cloud slot")
local GLM = "allow_remote: true\ncloud_backend: openai\n" ..
            "cloud_base_url: https://open.bigmodel.cn/api/paas/v4\ncloud_model: glm-4-flash\n" ..
            "cloud_api_key_account: ime-translate-zhipu\ncloud_timeout_ms: 2500\n"
local g, wg = load(GLM)
eq(#wg, 0, "a valid cloud slot warns nothing")
eq(g.backend, "libretranslate", "the local backend is untouched")
eq(g.base_url, "http://127.0.0.1:8989", "the local base_url is untouched")
eq(g.timeout_ms, 1500, "the local timeout is untouched")
eq(g.api_key_account, "", "the local account is untouched")
eq(g.cloud.backend, "openai", "cloud backend")
eq(g.cloud.base_url, "https://open.bigmodel.cn/api/paas/v4", "cloud base_url")
eq(g.cloud.model, "glm-4-flash", "cloud model")
eq(g.cloud.api_key_account, "ime-translate-zhipu", "cloud account")
eq(g.cloud.timeout_ms, 2500, "cloud timeout")
eq(g.cloud.allow_remote, true, "allow_remote is shared")
eq(g.cloud.temperature, 0.2, "an unset cloud key takes the default")
assert(g.cloud.prompt:find("只输出译文"), "the cloud slot gets the default prompt")
eq(g.cloud.cloud, nil, "the cloud slot holds no slot of its own")
for key in pairs(load(nil)) do
  eq(g.cloud[key] ~= nil, true, "the cloud slot has " .. key)
end
-- unset cloud keys take the defaults, not the local slot's values
local u = load("timeout_ms: 900\nmodel: local-m\ncloud_backend: libretranslate\n")
eq(u.cloud.timeout_ms, 1500, "cloud timeout is the default, not the local 900")
eq(u.cloud.model, "", "cloud model is the default, not the local one")
eq(u.cloud.base_url, "http://127.0.0.1:8989", "cloud base_url defaults to loopback")
-- the shared keys come from the unprefixed ones
local sh = load("max_chars: 50\ndebug_log: true\ncloud_backend: libretranslate\n")
eq(sh.cloud.max_chars, 50, "max_chars is shared")
eq(sh.cloud.debug_log, true, "debug_log is shared")
eq(load("max_chars: 0\ncloud_backend: libretranslate\n").cloud.max_chars, 2000,
   "the shared max_chars is range-checked before it is shared")
-- a cloud slot that fails a check is dropped, never replaced by translate
local nr, wnr = load("cloud_backend: openai\ncloud_base_url: https://open.bigmodel.cn/api/paas/v4\n")
eq(nr.cloud, nil, "remote cloud without allow_remote: no cloud slot")
eq(#wnr, 1, "the drop warns once")
eq(nr.backend, "libretranslate", "the local slot is untouched by the drop")
local ht, wht = load("allow_remote: true\ncloud_backend: openai\ncloud_base_url: http://api.example.com/v1\n")
eq(ht.cloud, nil, "plain http cloud: no cloud slot")
eq(#wht, 1, "the plain http drop warns once")
local ub, wub = load("cloud_backend: Openai\n")
eq(ub.cloud, nil, "unknown cloud backend: no cloud slot")
eq(#wub, 1, "the unknown cloud backend warns once")
for _, w in ipairs({ wnr[1], wht[1], wub[1] }) do
  assert(not w:find("bigmodel") and not w:find("example") and not w:find("Openai"),
         "a drop warning names no value: " .. w)
end
-- the range check resets, as for the local slot
local ct, wct = load("cloud_backend: libretranslate\ncloud_timeout_ms: 99999\n")
eq(ct.cloud.timeout_ms, 1500, "a cloud timeout out of range resets")
eq(#wct, 1, "the reset warns")
-- cloud_ keys with no cloud_backend: no slot, one warning
local nb, wnb = load("cloud_model: m\ncloud_timeout_ms: 2000\n")
eq(nb.cloud, nil, "no cloud_backend: no cloud slot")
eq(#wnb, 1, "cloud keys without cloud_backend warn once")
eq(nb.model, "", "a cloud_ key never lands in the local slot")
-- a shared key under the prefix is unknown, not quietly shared
local sk, wsk = load("cloud_backend: libretranslate\ncloud_allow_remote: true\n")
eq(#wsk, 1, "cloud_allow_remote is an unknown key")
assert(wsk[1]:find("cloud_allow_remote"), "the warning names the prefixed key")
eq(sk.cloud.allow_remote, false, "cloud_allow_remote does not turn remote on")
-- the prefix is exact
local _, wpx = load("cloudbackend: openai\n")
eq(#wpx, 1, "cloudbackend is an unknown key")
-- a bad cloud value warns under its prefixed name
local _, wnn = load("cloud_backend: libretranslate\ncloud_timeout_ms: abc\n")
eq(#wnn, 1, "a non-numeric cloud value warns")
assert(wnn[1]:find("cloud_timeout_ms"), "the warning names cloud_timeout_ms")
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `lua tests/test_config.lua`
Expected: FAIL at `a valid cloud slot warns nothing`. Every `cloud_` key is an
unknown key today, so `#wg` is 5 or 6, not 0.

- [ ] **Step 3: Implement**

In `rime/lua/ime_translate/config.lua`, after the `BACKENDS` line:

```lua
-- Feature 003 (backend.md §9): the keys each backend slot owns. The cloud slot
-- is the same set under the cloud_ prefix; every other key is shared.
local SLOT_KEYS = { backend = true, base_url = true, model = true, prompt = true,
                    timeout_ms = true, temperature = true, max_tokens = true,
                    api_key_account = true }
local CLOUD = "cloud_"
```

After `is_loopback`'s export, a function holding the two checks that used to
be inline in `load`:

```lua
-- One slot's adapter and trust checks: the reason it fails, or nil. A reason
-- names keys, never values (design §7.3).
local function refusal(s)
  -- An unknown adapter name would make every Enter fail with no reason logged.
  if not BACKENDS[s.backend] then return "unknown backend" end
  -- Tiered trust: loopback only by default; remote needs allow_remote, and
  -- remote must be https.
  if not is_loopback(s.base_url) then
    if not s.allow_remote then return "non-loopback base_url needs allow_remote: true" end
    if not s.base_url:find("^https://") then return "remote base_url must use https" end
  end
  return nil
end
```

In `M.load`, next to `local warnings = {}`:

```lua
  local cloud = {}   -- the cloud_ keys given, under their bare names
```

In the parse loop, the `if take then` block routes a `cloud_` slot key to
`cloud`, and every branch writes to `dest[key]`. The warnings keep the key as
written:

```lua
        if take then
          local dest, key = out, k
          if k:sub(1, #CLOUD) == CLOUD and SLOT_KEYS[k:sub(#CLOUD + 1)] then
            dest, key = cloud, k:sub(#CLOUD + 1)
          end
          if DEFAULTS[key] == nil then
            warnings[#warnings + 1] = "unknown config key: " .. k
          elseif BOOLS[key] then
            -- true or false only. Anything else resets to the default (both
            -- bools default to false, so this fails closed) and warns -- it must
            -- not leave an earlier line's "true" standing.
            local lv = v:lower()
            if lv == "true" then dest[key] = true
            elseif lv == "false" then dest[key] = false
            else
              dest[key] = DEFAULTS[key]
              warnings[#warnings + 1] = "not true or false: " .. k
            end
          elseif NUMS[key] then
            local num = tonumber(v)
            if num then dest[key] = num else warnings[#warnings + 1] = "not a number: " .. k end
          else
            dest[key] = v
          end
        end
```

Replace the two inline checks after the loop (the unknown backend and the trust
tier) with:

```lua
  local why = refusal(out)
  if why then
    warnings[#warnings + 1] = why .. "; fell back to the default backend"
    -- the triple falls back together: a libretranslate URL under the openai
    -- adapter would fail with a misleading error
    out.backend, out.base_url, out.model = DEFAULTS.backend, DEFAULTS.base_url, DEFAULTS.model
  end
```

The `timeout_ms` and `max_chars` range checks stay as they are. After them,
before `return out, warnings`:

```lua
  -- Feature 003 (backend.md §9): the cloud slot exists only when cloud_backend
  -- is set. It starts from the defaults, not from the local slot, and takes
  -- the shared keys from the local one, already checked. One that fails a
  -- check is dropped, never replaced by the default backend: that would make
  -- "cloud" silently mean translate.
  if cloud.backend then
    local s = {}
    for k, v in pairs(DEFAULTS) do
      if SLOT_KEYS[k] then s[k] = v else s[k] = out[k] end
    end
    for k, v in pairs(cloud) do s[k] = v end
    local cwhy = refusal(s)
    if cwhy then
      warnings[#warnings + 1] = "cloud slot dropped: " .. cwhy
    else
      if s.timeout_ms < 500 or s.timeout_ms > 10000 then
        warnings[#warnings + 1] = "cloud_timeout_ms out of range [500,10000]; fell back to default"
        s.timeout_ms = DEFAULTS.timeout_ms
      end
      out.cloud = s
    end
  elseif next(cloud) then
    warnings[#warnings + 1] = "cloud_ keys without cloud_backend; no cloud slot"
  end
```

- [ ] **Step 4: Run it and confirm it passes**

Run: `lua tests/test_config.lua && scripts/run_tests.sh`
Expected: `test_config: … assertions OK`, and every file PASS. The existing
assertions pass unchanged: the local slot's warnings and fallbacks are the same
strings and counts.

- [ ] **Step 5: Commit**

```bash
git add rime/lua/ime_translate/config.lua tests/test_config.lua
git commit -m "feat: a cloud_ backend slot in the config"
```

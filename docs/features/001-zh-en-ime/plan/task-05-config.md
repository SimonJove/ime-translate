# Task 5: Config loading and validation (TDD)

**Files:**
- Create: `rime/lua/ime_translate/config.lua`
- Test: `tests/test_config.lua`

**Interfaces:**
- Consumes: nothing
- Produces: `config.load(read_fn) -> settings, warnings`, where
  `read_fn() -> string|nil` (nil means unreadable, so use defaults). `settings`
  fields: `backend base_url model prompt timeout_ms max_chars temperature
  max_tokens allow_remote api_key_account debug_log`. A field that fails
  validation falls back to its default and produces a warning.

> **Two defaults that are easy to get wrong**: `timeout_ms` = `1500` (design
> §8.2 — the timeout value *is* the worst-case freeze after Enter; it is not
> 3000); and there is **no** `toggle_keycode` / `toggle_modifier` — schema
> switching belongs to Rime's native `key_binder`, and Lua never reads those
> keys.

> The default prompt stays Chinese: it addresses a model translating Chinese
> input, and rewriting it in English would change the artifact under test.

- [ ] **Step 1: Write the failing test**

`tests/test_config.lua`:

```lua
package.path = package.path .. ";rime/lua/?.lua"
local config = require("ime_translate.config")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end
local function load(text) return config.load(function() return text end) end

-- defaults
local d = load(nil)
eq(d.backend, "libretranslate", "default backend is translate (decision D4)")
eq(d.base_url, "http://127.0.0.1:8989", "default base_url")
eq(d.model, "", "default model: libretranslate takes none")
eq(d.timeout_ms, 1500, "default timeout is 1500, not 3000")
eq(d.max_chars, 2000, "default max_chars")
eq(d.temperature, 0.2, "default temperature")
eq(d.max_tokens, 1024, "default max_tokens")
eq(d.allow_remote, false, "default allow_remote off")
eq(d.api_key_account, "", "default api_key_account empty")
eq(d.debug_log, false, "default debug_log")
eq(d.toggle_keycode, nil, "toggle keys are not this project's config")
assert(d.prompt:find("只输出译文"), "default prompt present")

-- parsing
local p = load("timeout_ms: 900\nmax_chars: 50\ndebug_log: true\nmodel: foo\n")
eq(p.timeout_ms, 900, "parse int")
eq(p.max_chars, 50, "parse int 2")
eq(p.debug_log, true, "parse bool")
eq(p.model, "foo", "parse string")

-- comments and blank lines are ignored
local c = load("# comment\n\n   # indented comment\nmodel: bar\n")
eq(c.model, "bar", "comments ignored")

-- an unknown key warns rather than being silently dropped
local _, w1 = load("nonsense_key: 1\n")
eq(#w1, 1, "unknown key warns")
assert(w1[1]:find("nonsense_key"), "warning names the key")

-- non-numeric warns and falls back
local b, w2 = load("timeout_ms: abc\n")
eq(b.timeout_ms, 1500, "non-numeric falls back")
eq(#w2, 1, "non-numeric warns")

-- out of range falls back
local o1 = load("timeout_ms: 99\n");    eq(o1.timeout_ms, 1500, "timeout below floor")
local o2 = load("timeout_ms: 99999\n"); eq(o2.timeout_ms, 1500, "timeout above ceiling")
local o3 = load("max_chars: 0\n");      eq(o3.max_chars, 2000, "max_chars below floor")
local o4 = load("max_chars: 99999\n");  eq(o4.max_chars, 2000, "max_chars above ceiling")

-- tiered trust: non-loopback without allow_remote is refused and falls back
local r1, wr1 = load("backend: anthropic\nbase_url: https://api.anthropic.com/v1\n")
eq(r1.base_url, "http://127.0.0.1:8989", "remote rejected without allow_remote")
eq(r1.backend, "libretranslate", "the whole backend falls back, not only base_url")
eq(#wr1, 1, "rejection warns")
-- allow_remote plus https is accepted
local r2 = load("allow_remote: true\nbase_url: https://api.anthropic.com/v1\n")
eq(r2.base_url, "https://api.anthropic.com/v1", "https remote accepted")
-- allow_remote but plaintext http is still refused
local r3, wr3 = load("allow_remote: true\nbackend: openai\nbase_url: http://api.example.com/v1\n")
eq(r3.base_url, "http://127.0.0.1:8989", "plain http remote rejected even with allow_remote")
eq(r3.backend, "libretranslate", "the whole backend falls back, not only base_url")
eq(#wr3, 1, "plain http rejection warns")
-- localhost counts as loopback
local r4 = load("base_url: http://localhost:8989\n")
eq(r4.base_url, "http://localhost:8989", "localhost is loopback")
-- https on loopback is fine too
local r5 = load("base_url: https://127.0.0.1:11434/v1\n")
eq(r5.base_url, "https://127.0.0.1:11434/v1", "https loopback fine")

-- api_key_account is kept verbatim and never interpreted
local k = load("api_key_account: anthropic\n")
eq(k.api_key_account, "anthropic", "account name kept verbatim")
print(("test_config: %d assertions OK"):format(n))
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `lua tests/test_config.lua`
Expected: FAIL (module not found)

- [ ] **Step 3: Implement**

`rime/lua/ime_translate/config.lua`:

```lua
-- Flat key: value config (one per line, # comments). Only keys documented
-- in this file are accepted.
local M = {}

local DEFAULT_PROMPT = "你是翻译器。把用户的中文翻译成自然、简洁、适合即时聊天语境的英文。" ..
  "只输出译文——不要解释、不要引号、不要前缀。保留语气、emoji、数字、URL、代码标识符和换行。" ..
  "如果文本基本没有中文，原样返回。"

local DEFAULTS = {
  -- decision D4: translate is the default; apfel cannot run on the dev machine
  backend = "libretranslate",   -- openai | libretranslate | anthropic
  base_url = "http://127.0.0.1:8989",
  model = "",              -- libretranslate takes no model
  prompt = DEFAULT_PROMPT,
  -- design §8.2: under a synchronous blocking model this value IS the IME's
  -- worst-case freeze after Enter. Local default 1500ms; past one second the
  -- experience has already collapsed, and waiting until three only prolongs it.
  timeout_ms = 1500,
  max_chars = 2000,        -- characters, not bytes
  -- Available to adapters, but **each adapter decides whether to send it**.
  -- Claude Opus 5 / Sonnet 5 removed the parameter; sending it returns 400.
  temperature = 0.2,
  max_tokens = 1024,       -- required by the anthropic adapter
  allow_remote = false,    -- when false, any non-loopback base_url is refused
  api_key_account = "",    -- the Keychain account name; never the secret itself
  debug_log = false,
}

local BOOLS = { debug_log = true, allow_remote = true }
local NUMS = { timeout_ms = true, max_chars = true, temperature = true, max_tokens = true }

local function is_loopback(url)
  return url:find("^https?://127%.0%.0%.1") ~= nil
      or url:find("^https?://localhost") ~= nil
end

function M.load(read_fn)
  local out = {}
  for k, v in pairs(DEFAULTS) do out[k] = v end
  local warnings = {}
  local raw = read_fn()
  if raw then
    for line in raw:gmatch("[^\r\n]+") do
      if not line:match("^%s*#") then
        local k, v = line:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
        if k and v ~= "" then
          if DEFAULTS[k] == nil then
            warnings[#warnings + 1] = "unknown config key: " .. k
          elseif BOOLS[k] then
            out[k] = (v == "true")
          elseif NUMS[k] then
            local num = tonumber(v)
            if num then out[k] = num else warnings[#warnings + 1] = "not a number: " .. k end
          else
            out[k] = v
          end
        end
      end
    end
  end
  -- Tiered trust: loopback only by default; remote needs allow_remote, and
  -- remote must be https.
  if not is_loopback(out.base_url) then
    if not out.allow_remote then
      warnings[#warnings + 1] = "non-loopback base_url needs allow_remote: true; fell back to the default backend"
      -- the triple falls back together: a libretranslate URL under the openai
      -- adapter would fail with a misleading error
      out.backend, out.base_url, out.model = DEFAULTS.backend, DEFAULTS.base_url, DEFAULTS.model
    elseif not out.base_url:find("^https://") then
      warnings[#warnings + 1] = "remote base_url must use https; fell back to the default backend"
      out.backend, out.base_url, out.model = DEFAULTS.backend, DEFAULTS.base_url, DEFAULTS.model
    end
  end
  if out.timeout_ms < 500 or out.timeout_ms > 10000 then
    warnings[#warnings + 1] = "timeout_ms out of range [500,10000]; fell back to default"
    out.timeout_ms = DEFAULTS.timeout_ms
  end
  if out.max_chars < 1 or out.max_chars > 5000 then
    warnings[#warnings + 1] = "max_chars out of range [1,5000]; fell back to default"
    out.max_chars = DEFAULTS.max_chars
  end
  return out, warnings
end

return M
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `lua tests/test_config.lua && scripts/run_tests.sh`
Expected: `test_config: 33 assertions OK`, whole suite PASS

- [ ] **Step 5: Commit**

```bash
git add rime/lua/ime_translate/config.lua tests/test_config.lua
git commit -m "feat: config loading with tiered trust, timeout default 1500"
```

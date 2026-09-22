# Task 3: The raw candidate (TDD)

**Files:**
- Create: `rime/lua/ime_translate_raw.lua`
- Test: `tests/test_raw.lua`
- Modify: `tests/test_glue_load.lua` (the module list)

**Interfaces:**
- Consumes the rime globals `yield` and `Candidate`, and
  `env.engine.context:get_option("ascii_mode")`, but only when called, never
  at load, so it loads headless.
- Produces the rime component module `ime_translate_raw`, a translator function
  `(input, seg, env)`. Task 5 binds it in `rime.lua` and adds
  `lua_translator@ime_translate_raw` to the schema.

In English mode, `ascii_segmentor` tags the segment `raw`, and no stock
translator offers anything for it. So confirming the segment has nothing to
select, and the lock in Task 4 would do nothing.

The translator answers only in English mode. In Chinese mode,
`fallback_segmentor` also tags the characters no other segmentor claims `raw`
(upstream F19, a source reading). A candidate there would open a menu that
feature 001 never showed.

This translator yields the typed letters as the segment's only candidate. The
spike showed that confirming it keeps the English literal across the switch
back to pinyin: `今天readme好的`, `请pull request好的` (design §5.5). The
candidate is text only and never committed by the engine; the processor still
owns every commit.

- [ ] **Step 1: Write the failing test**

`tests/test_raw.lua`:

```lua
package.path = package.path .. ";rime/lua/?.lua"
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

-- rime's globals, faked: yield collects, Candidate builds a plain table
local yielded
_G.yield = function(c) yielded[#yielded + 1] = c end
_G.Candidate = function(type_, start, _end, text, comment)
  return { type = type_, start = start, _end = _end, text = text, comment = comment }
end
local translator = require("ime_translate_raw")
eq(type(translator), "function", "the module is a translator function")

local function seg(tags, start, _end)
  return { start = start, _end = _end,
           has_tag = function(self, t) return tags[t] == true end }
end
-- env.engine.context, holding only the mode
local function env(ascii)
  return { engine = { context = {
    get_option = function(_, name) return name == "ascii_mode" and ascii end } } }
end
local ENGLISH, CHINESE = env(true), env(false)

-- an English-mode segment: exactly one candidate, the letters as typed
yielded = {}
translator("git status", seg({ raw = true }, 6, 16), ENGLISH)
eq(#yielded, 1, "one candidate for a raw segment")
eq(yielded[1].text, "git status", "the letters verbatim, spaces kept")
eq(yielded[1].start, 6, "candidate starts where the segment does")
eq(yielded[1]._end, 16, "candidate ends where the segment does")
eq(yielded[1].type, "raw", "candidate type raw")

-- case is kept as typed
yielded = {}
translator("README", seg({ raw = true }, 0, 6), ENGLISH)
eq(yielded[1].text, "README", "upper case kept")

-- Chinese mode: a raw segment is fallback_segmentor's leftover (F19), left
-- as in feature 001; a pinyin segment is the stock translators'
yielded = {}
translator("'", seg({ raw = true }, 7, 8), CHINESE)
eq(#yielded, 0, "nothing for a raw segment in Chinese mode")
translator("jintian", seg({ abc = true }, 0, 7), CHINESE)
eq(#yielded, 0, "nothing for a pinyin segment")
print(("test_raw: %d assertions OK"):format(n))
```

In `tests/test_glue_load.lua`, add the module to the list, and adjust the final
message:

```lua
local names = { "ime_translate_shared", "ime_translate_processor", "ime_translate_raw" }
```

```lua
print("test_glue_load: 3 modules OK, shared is lazy and stateless")
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `lua tests/test_raw.lua; lua tests/test_glue_load.lua`
Expected: both FAIL, with `module 'ime_translate_raw' not found`.

- [ ] **Step 3: Implement**

`rime/lua/ime_translate_raw.lua`:

```lua
-- Translator, feature 002 (design §5.5). In English mode ascii_segmentor tags
-- the segment "raw" and no stock translator offers anything for it, so there
-- would be nothing to confirm when the processor locks it. This yields the
-- typed letters as its only candidate. Chinese mode is left as it was:
-- fallback_segmentor tags its leftovers "raw" there too (upstream F19).
-- Display and lock only: the processor still owns every commit.
local function translator(input, seg, env)
  if seg:has_tag("raw") and env.engine.context:get_option("ascii_mode") then
    yield(Candidate("raw", seg.start, seg._end, input, ""))
  end
end

return translator
```

- [ ] **Step 4: Run them and confirm they pass**

Run: `lua tests/test_raw.lua && lua tests/test_glue_load.lua && scripts/run_tests.sh`
Expected: `test_raw: 9 assertions OK`,
`test_glue_load: 3 modules OK, shared is lazy and stateless`, and every file
PASS.

- [ ] **Step 5: Commit**

```bash
git add rime/lua/ime_translate_raw.lua tests/test_raw.lua tests/test_glue_load.lua
git commit -m "feat: raw candidate for an English-mode segment"
```

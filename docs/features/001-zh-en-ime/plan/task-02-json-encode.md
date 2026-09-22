# Task 2: Scaffolding + JSON string encoding (TDD)

**Files:**
- Create: `.gitignore`, `scripts/run_tests.sh`
- Create: `rime/lua/ime_translate/json.lua`
- Test: `tests/test_json_encode.lua`

**Interfaces:**
- Consumes: nothing
- Produces: `json.escape(s) -> string` (returns a quoted JSON string literal);
  `json.shq(s) -> string` (POSIX single-quote shell escaping)

- [ ] **Step 1: Directories and scaffolding**

```bash
mkdir -p rime/lua/ime_translate tests scripts eval launchd
# .gitignore already exists from the harness (*.log, /tmp/, .claude/ local
# state, .DS_Store). Append rather than overwrite: `cat >` would wipe those.
grep -q '^eval/results-' .gitignore || printf 'eval/results-*.md\n' >> .gitignore
cat > scripts/run_tests.sh <<'EOF'
#!/bin/bash
# Run every headless unit test; non-zero exit if any fails.
set -u
cd "$(dirname "$0")/.."
fail=0
for f in tests/test_*.lua; do
  if lua "$f"; then echo "PASS $f"; else echo "FAIL $f"; fail=1; fi
done
exit $fail
EOF
chmod +x scripts/run_tests.sh
```

- [ ] **Step 2: Write the failing test**

`tests/test_json_encode.lua`:

```lua
package.path = package.path .. ";rime/lua/?.lua"
local json = require("ime_translate.json")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

eq(json.escape("hello"), '"hello"', "plain")
eq(json.escape('say "hi"'), '"say \\"hi\\""', "double quote")
eq(json.escape("line1\nline2"), '"line1\\nline2"', "newline")
eq(json.escape("tab\t"), '"tab\\t"', "tab")
eq(json.escape("back\\slash"), '"back\\\\slash"', "backslash")
eq(json.escape("中文"), '"中文"', "raw utf8 passthrough")
eq(json.shq("plain"), "'plain'", "shq plain")
eq(json.shq("it's"), "'it'\\''s'", "shq single quote")
eq(json.shq("a$b`c"), "'a$b`c'", "shq metachars")
eq(json.shq('x"y'), "'x\"y'", "shq double quote stays literal")
print(("test_json_encode: %d assertions OK"):format(n))
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `lua tests/test_json_encode.lua`
Expected: FAIL (`module 'ime_translate.json' not found`)

- [ ] **Step 4: Minimal implementation**

`rime/lua/ime_translate/json.lua`:

```lua
-- A pure-Lua JSON subset: escape/shq for encoding, decode for parsing (Task 3).
local M = {}

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
                  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

function M.escape(s)
  local out = s:gsub('[%c"\\]', function(c)
    return escapes[c] or ("\\u%04X"):format(string.byte(c))
  end)
  return '"' .. out .. '"'
end

-- POSIX single-quote safety: it's -> 'it'\''s'
-- The project's only shell-escaping entry point. Never use
-- string.format("%q", ...) -- that is Lua literal escaping, it produces double
-- quotes, and $() and backticks still expand inside them in a shell.
function M.shq(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

return M
```

- [ ] **Step 5: Run it and confirm it passes**

Run: `lua tests/test_json_encode.lua`
Expected: `test_json_encode: 10 assertions OK`

- [ ] **Step 6: Commit**

```bash
git add .gitignore scripts/run_tests.sh rime/lua/ime_translate/json.lua tests/test_json_encode.lua
git commit -m "feat: scaffolding and JSON string encoding"
```

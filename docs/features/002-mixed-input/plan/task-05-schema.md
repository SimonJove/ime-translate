# Task 5: Schema and installer

**Files:**
- Modify: `rime/luna_pinyin_translate.schema.yaml` (header changes 2 and 8,
  new change 9 — `Caps_Lock: noop`, `description`)
- Modify: `scripts/install.sh` (the `rime.lua` binding; the closing hint)
- Delete: `rime/lua/ime_translate_raw.lua`, `tests/test_raw.lua` (D8)
- Modify: `tests/test_glue_load.lua` (the module list, back to two)
- Modify: `docs/design/architecture.md` (one line in §5.2: feature 002 is
  built)

**Interfaces:**
- Consumes: the processor's Shift tap (Task 4) and the Enter way (Task 7).
- Produces: an installed schema in which the processor owns Enter, Space and
  the Shift tap, and Caps Lock only types capitals. Task 6 observes it.

This task was revised on 2026-09-22, before it started, when D7 and D8 closed
(decisions.md, "Feature 002 redesigned").
- **D7:** Caps Lock is `noop` in this schema.
- **D8:** the raw translator is dropped, so the schema gains no translator
  line, and the module and its test go.

The installer still binds **every** Lua component the schema names, read from
the schema itself. Today that is only the processor; a component added later
is bound with no second list to keep in step.

The rest of this task is on the real machine, as 001 Task 10 was. `install.sh`
writes into `~/Library/Rime`.

- [ ] **Step 1: The schema**

In `rime/luna_pinyin_translate.schema.yaml`, replace change 2 of the header:

```yaml
#   2. The Lua processor comes first so it sees every key ahead of everything
#      else, ascii_composer included: Enter, Space and the Shift tap. It shows
#      the translation in the prompt (decision D1).
```

replace change 8, and add change 9:

```yaml
#   8. ascii_composer's Shift_L and Shift_R are noop. With the processor first,
#      ascii_composer never saw the Enter of Shift+Enter and took the Shift
#      release for a lone tap, switching the IME to English (found in use,
#      2026-09-21; the user's fix). The processor owns the Shift tap instead,
#      and it does see every key (feature 002, design §5.5).
#   9. Caps Lock is noop (decision D7): it only types capitals, which reach
#      the draft as letters in either mode. The inherited clear discarded an
#      open draft (001 smoke row 26), and after a Shift tap the next letter
#      would have replaced it (R16).
```

add one line to `description` (the schema's own text, Chinese as data):

```yaml
  description: |
    打中文，回车翻译，再回车上屏英文。
    Shift+回车 = 不翻译直接上中文。Esc = 弃译文继续编辑。
    拼音后回车 = 原样英文；空格 = 空格；单击 Shift = 中英切换。
    Ctrl+Shift+T 切回朙月拼音·简化字。
```

and in `ascii_composer/switch_key`, replace `Caps_Lock: clear`:

```yaml
    Caps_Lock: noop                           # 9.
```

- [ ] **Step 2: The installer**

In `scripts/install.sh`, replace the whole `rime.lua` block, from its comment
through the closing `fi`:

```bash
# rime.lua: librime-lua resolves lua_processor@NAME and lua_translator@NAME to
# a Lua global of that name defined here. Without it the component is created
# with no error and never runs (spike report, "Deviations from the plan"). The
# names are read from the schema, so a component added there is bound here.
names=$(sed -n 's/^ *- lua_[a-z]*@\([A-Za-z0-9_]*\).*/\1/p' rime/luna_pinyin_translate.schema.yaml)
[ -n "$names" ] || { echo "FAILED: no Lua component found in the schema" >&2; exit 1; }
touch "$RIME/rime.lua"
for name in $names; do
  BIND="$name = require(\"$name\")"
  if ! grep -qxF "$BIND" "$RIME/rime.lua"; then
    if [ -s "$RIME/rime.lua" ] && [ -n "$(tail -c1 "$RIME/rime.lua")" ]; then
      echo >> "$RIME/rime.lua"
    fi
    printf '%s\n' "$BIND" >> "$RIME/rime.lua"
    echo "bound $name in $RIME/rime.lua"
    lua_changed=1
  fi
done
```

and extend the last line of the closing hint:

```bash
Then Ctrl+Shift+T switches between luna_pinyin_simp and the translation schema.
In the translation schema, Enter after pinyin keeps it as English letters, and
a Shift tap switches between Chinese and English.
```

- [ ] **Step 3: Drop the raw translator (D8)**

```bash
git rm rime/lua/ime_translate_raw.lua tests/test_raw.lua
```

In `tests/test_glue_load.lua`, put the module list and the final message back:

```lua
local names = { "ime_translate_shared", "ime_translate_processor" }
```

```lua
print("test_glue_load: 2 modules OK, shared is lazy and stateless")
```

- [ ] **Step 4: The static checks**

```bash
bash -n scripts/install.sh && echo syntax ok
sed -n 's/^ *- lua_[a-z]*@\([A-Za-z0-9_]*\).*/\1/p' rime/luna_pinyin_translate.schema.yaml
grep -n 'Caps_Lock' rime/luna_pinyin_translate.schema.yaml
scripts/run_tests.sh
```

Expected:
- `syntax ok`
- exactly one name, `ime_translate_processor`
- the single `Caps_Lock: noop` line
- every test file PASS, ten of them

- [ ] **Step 5: Install, twice**

```bash
touch "$TMPDIR/ime-002-t5.stamp"
./scripts/install.sh
./scripts/install.sh
grep -c 'require("ime_translate_' ~/Library/Rime/rime.lua
grep -n 'Caps_Lock' ~/Library/Rime/build/luna_pinyin_translate.schema.yaml
find "$TMPDIR" -name 'rime.squirrel.*.log.ERROR.*' -newer "$TMPDIR/ime-002-t5.stamp"
```

Expected:
- **The first run** installs `shift_tap.lua`, the changed Lua files and the
  schema. It prints no `bound` line, since 001 bound the processor already.
  Then it prints the restart notice.
- **The second run** prints no `installed` and no `bound` line.
- **`rime.lua`** holds 1 matching line.
- **The built schema** has `Caps_Lock: noop`.
- **The `find`** prints nothing: the deploy logged no error.

- [ ] **Step 6: Restart Squirrel**

With no draft open in any application (an open draft is committed as raw
pinyin), run:

```bash
"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --quit
```

Then switch to another app and back, so that the system relaunches it. With
Squirrel as the input source in TextEdit, type `jintian`, press space, type
`readme`, press Enter, then Esc.

```bash
find "$TMPDIR" -name 'rime.squirrel.*.log.ERROR.*' -newer "$TMPDIR/ime-002-t5.stamp"
```

Expected:
- The preedit shows `今天readme`, with no candidate window, before Esc.
- The `find` prints nothing.

A Lua error inside the processor reaches no Rime log (F27). A wrong preedit
here is therefore the only sign of it: with an error, Enter falls through to
the old behaviour and translates.

- [ ] **Step 7: The design says it is built**

In `docs/design/architecture.md` §5.2, replace:

```markdown
- Feature 002 is meant to give the Shift tap back, handled by the processor
  (§5.5; designed with the user on 2026-09-21, not yet built).
```

with:

```markdown
- Feature 002 gives the Shift tap back, handled by the processor (§5.5).
```

- [ ] **Step 8: Commit**

```bash
git add rime/luna_pinyin_translate.schema.yaml scripts/install.sh \
        tests/test_glue_load.lua docs/design/architecture.md
git commit -m "feat: wire feature 002 into the schema; Caps Lock only types capitals"
```

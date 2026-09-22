# Task 1: Phase 0 spike — verify the foundations of Plan A′

One-off. The probe code is thrown away and never enters the repo.

**Files:**
- Create: `/tmp/ime_spike/` (disposable, **not in git**)
- Create: `docs/spike-report.md` (the conclusions do go in git)

**Interfaces:**
- Consumes: nothing
- Produces: the spike report — the S1–S14 verdicts, the real version numbers,
  and the constants later tasks need (`kNoop` / `kAccepted` values, the KeyEvent
  and Context API surface, **the display mechanism S11 selected**)

> S11–S14 (Steps 7 and 8) were added by the design review of 2026-09-20
> ([design §13](../../../design/decisions.md)). Read
> [design §15](../../../design/upstream.md) first: it says what upstream source
> leads us to *expect* from S1, S2, S5 and S11. An expectation is not a verdict —
> the report records what was seen, and says so where the two differ.

> **S1, S3 and S11 are life-or-death** (S11 by decision D3, design §13). If S1
> or S3 fails, Plan A′ does not exist: stop implementing and return to design to
> evaluate Plan B′ (Lua-owned draft). If S11 fails, design §6.1–§6.2 go back to
> design review before any implementation continues — A′ itself may still stand.
> Do not amend the design yourself and carry on.

**This task needs a human at the machine.** Installing the IME, adding the input
source in System Settings, and watching what actually appears in an
application's input box cannot be delegated. An agent supplies commands and
criteria; the user runs them and reports what they saw.

- [ ] **Step 1: Install the environment, record versions**

```bash
brew install --cask squirrel
brew install lua
brew install apfel                      # default backend candidate A
sw_vers
ls -l "/Library/Input Methods/Squirrel.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
  "/Library/Input Methods/Squirrel.app/Contents/Info.plist"
# System Settings -> Keyboard -> Input Sources: add Squirrel
# Squirrel menu -> Settings -> turn on inline_preedit
#   (or edit ~/Library/Rime/squirrel.custom.yaml)
```

Write the Squirrel, librime and librime-lua versions into the report's opening
paragraph. All later re-verification is measured against these versions.

- [ ] **Step 2: S9 + S10 — io.popen and multi-file require**

```bash
mkdir -p ~/Library/Rime/lua/spike_pkg
cat > ~/Library/Rime/lua/spike_pkg/child.lua <<'EOF'
return { tag = "child-ok" }
EOF
cat > ~/Library/Rime/lua/spike_probe.lua <<'EOF'
-- Probe processor: on any key, log the probe results, then pass through.
local child_ok, child = pcall(require, "spike_pkg.child")
local function log(msg)
  local f = io.open(os.getenv("HOME") .. "/spike.log", "a")
  if f then f:write(os.date("%H:%M:%S "), msg, "\n"); f:close() end
end
local done = false
return function(key, env)
  if not done then
    done = true
    log("S10 require subdir: " .. tostring(child_ok) .. " " ..
        (child_ok and tostring(child.tag) or tostring(child)))
    local p = io.popen("curl -sS --max-time 2 http://127.0.0.1:11434/v1/models; echo EXIT=$?", "r")
    log("S9 io.popen curl: " .. (p and (p:read("*a") or "nil") or "popen failed"))
    if p then p:close() end
  end
  return 2 -- kNoop
end
EOF
cat > ~/Library/Rime/luna_pinyin.custom.yaml <<'EOF'
patch:
  engine/processors/@before 0: lua_processor@spike_probe
EOF
# Menu bar input icon -> "Redeploy"; switch to Squirrel and type any character
cat ~/spike.log
```

Criterion: `S10 require subdir: true child-ok`, and `S9` returns either an HTTP
response or an explicit curl exit code. Either failing means neither Plan A′ nor
B′ exists and only a fork remains.

- [ ] **Step 3: S3 + S4 — commit_text, Context properties, KeyEvent surface**

```bash
cat > ~/Library/Rime/lua/spike_probe.lua <<'EOF'
local function log(msg)
  local f = io.open(os.getenv("HOME") .. "/spike.log", "a")
  if f then f:write(os.date("%H:%M:%S "), msg, "\n"); f:close() end
end
local done = false
return function(key, env)
  local ctx = env.engine.context
  if not done then
    done = true
    -- S3: does engine:commit_text exist
    log("S3 commit_text type: " .. type(env.engine.commit_text))
    -- S4: Context property round trip
    log("S4 set_property type: " .. type(ctx.set_property) ..
        " get_property type: " .. type(ctx.get_property))
    local ok = pcall(function()
      ctx:set_property("spike.k", "v1")
      log("S4 roundtrip: " .. tostring(ctx:get_property("spike.k")))
      ctx:clear()
      log("S4 survives ctx:clear: " .. tostring(ctx:get_property("spike.k")))
    end)
    log("S4 pcall ok: " .. tostring(ok))
    -- KeyEvent surface: is release a method or a field
    log("KEY release type: " .. type(key.release) ..
        " keycode: " .. tostring(key.keycode) ..
        " modifier: " .. tostring(key.modifier))
    log("S3 get_commit_text type: " .. type(ctx.get_commit_text) ..
        " refresh type: " .. type(ctx.refresh_non_confirmed_composition))
  end
  -- On F8, commit a fixed English string to prove arbitrary text can commit
  if key.keycode == 0xFFC5 then
    env.engine:commit_text("HELLO FROM COMMIT_TEXT")
    ctx:clear()
    return 1 -- kAccepted
  end
  return 2
end
EOF
# Redeploy; type a few letters in TextEdit, then press F8
cat ~/spike.log
```

Criteria:

- **S3 passes** = `commit_text type: function`, and pressing F8 makes
  `HELLO FROM COMMIT_TEXT` appear in TextEdit. **Failing → Plan A′ does not
  exist; stop.**
- **S4 passes** = `set_property/get_property type: function` and the round trip
  prints `v1`. **Failing → fall back to "a module table keyed by
  `tostring(env.engine)` plus `fini` cleanup", record that downgrade in the
  report, and implement Task 7 accordingly.**
- Record `KEY release type`: `function` → the glue writes `key:release()`;
  `boolean` → it writes `key.release`. Task 9 follows this verdict.
- Record `S4 survives ctx:clear`: if properties outlive `ctx:clear()` (expected),
  Task 9's `commit_*` branches must call `session.clear(ctx)` explicitly.

- [ ] **Step 4: S1 + S2 — does fluid_editor really not commit early, and which path does punctuation take**

```bash
# A minimal translation schema first: swap only the editor, attach no lua
cp "/Library/Input Methods/Squirrel.app/Contents/SharedSupport/luna_pinyin.schema.yaml" \
   ~/Library/Rime/spike_fluid.schema.yaml
python3 - <<'PY'
import io,os
p=os.path.expanduser("~/Library/Rime/spike_fluid.schema.yaml")
s=io.open(p,encoding="utf-8").read()
s=s.replace("schema_id: luna_pinyin","schema_id: spike_fluid",1)
s=s.replace("express_editor","fluid_editor")
io.open(p,"w",encoding="utf-8").write(s)
print("express_editor occurrences (want 0):", s.count("express_editor"))
print("fluid_editor occurrences (want 1):", s.count("fluid_editor"))
PY
cat > ~/Library/Rime/default.custom.yaml <<'EOF'
patch:
  schema_list:
    - schema: luna_pinyin
    - schema: spike_fluid
EOF
rm -f ~/Library/Rime/luna_pinyin.custom.yaml
# Redeploy; Ctrl+` to switch to spike_fluid; open TextEdit
```

Do each of these in TextEdit and **watch what actually appears in the input
box** at every step:

| Action | S1/S2 criterion |
|---|---|
| Type `jintianyoudianlei`, press space to confirm `今天有点累` | The box should still show only preedit (underlined), **no committed black text** |
| Then type `buguo` and press `2` to pick the second candidate | Same; the draft keeps growing |
| Type a comma `,` | **The S2 question**: comma joins the preedit → S2 passes; the comma and everything before it turn into black committed text → S2 fails |
| Finish the sentence and press Enter | The whole sentence commits at once |

Criteria:

- **S1 passes** = no committed text appears in the box at any point during
  segment-by-segment selection. **Failing → Plan A′ does not exist; stop.**
- **S2 passes** = Chinese punctuation merges into the composition. Failing →
  record it, and Task 10's schema enables design §5.3's fallback.

**S2 is expected to fail** (design §15.2 F4): the stock preset defines the comma
as `{ commit: … }`, which commits whatever the editor is. So verify the fallback
here rather than meeting it for the first time in Task 10 — redefine the
committing marks as plain string values and repeat the comma row:

```bash
python3 - <<'PY'
import io,os
p=os.path.expanduser("~/Library/Rime/spike_fluid.schema.yaml")
s=io.open(p,encoding="utf-8").read()
# S2 fallback (design §5.3): plain string values confirm the selection instead
# of committing the composition. Extend the schema's existing punctuator:
# section in place -- appending a second one would be a duplicate key.
old = "punctuator:\n  import_preset: symbols\n"
new = old + """  half_shape:
    ',' : '，'
    '.' : '。'
    '?' : '？'
    '!' : '！'
    ';' : '；'
    ':' : '：'
    '^' : '……'
"""
print("punctuator sections patched (want 1):", s.count(old))
io.open(p,"w",encoding="utf-8").write(s.replace(old, new, 1))
PY
# Redeploy, repeat the comma row. "patched: 0" means the stock schema's
# punctuator section reads differently on this version: open the file, add the
# half_shape block under it by hand, and note the difference in the report.
```

- **S2 fallback passes** = the comma joins the preedit and the draft keeps
  growing past it. Record whether the preset's other marks (`<`, `/`, quotes)
  still behave — the patch is meant to merge per key, not to replace the map.
  Fallback fails too → record exactly what happened; design §5.3 goes back to
  review.

- [ ] **Step 5: S5 — can key_binder's select: switch both ways**

```bash
cat > ~/Library/Rime/default.custom.yaml <<'EOF'
patch:
  schema_list:
    - schema: luna_pinyin
    - schema: spike_fluid
  key_binder/bindings/+:
    - { when: always, accept: "Control+Shift+T", select: spike_fluid }
EOF
python3 - <<'PY'
import io,os
p=os.path.expanduser("~/Library/Rime/spike_fluid.schema.yaml")
s=io.open(p,encoding="utf-8").read()
s += '\nkey_binder:\n  bindings:\n    - { when: always, accept: "Control+Shift+T", select: luna_pinyin }\n'
io.open(p,"w",encoding="utf-8").write(s)
PY
# Redeploy; under luna_pinyin press Ctrl+Shift+T to reach spike_fluid,
# press it again to come back
```

Criterion: one hotkey switches both ways and the menu-bar schema name follows.
Failing → record it; Task 10 falls back to the `Ctrl+\`` schema menu and the
README states how to switch.

- [ ] **Step 6: S6 + S7 — ShadowCandidate comments, long preedit behaviour**

```bash
cat > ~/Library/Rime/lua/spike_probe.lua <<'EOF'
return function(input, env)
  local first = true
  for cand in input:iter() do
    if first then
      first = false
      local ok, shadow = pcall(function()
        return ShadowCandidate(cand, cand.type, cand.text, "✗ probe comment")
      end)
      local f = io.open(os.getenv("HOME") .. "/spike.log", "a")
      if f then f:write("S6 ShadowCandidate ok: ", tostring(ok), "\n"); f:close() end
      yield(ok and shadow or cand)
    else
      yield(cand)
    end
  end
end
EOF
python3 - <<'PY'
import io,os
p=os.path.expanduser("~/Library/Rime/spike_fluid.schema.yaml")
s=io.open(p,encoding="utf-8").read()
s=s.replace("filters:","filters:\n    - lua_filter@spike_probe",1)
io.open(p,"w",encoding="utf-8").write(s)
PY
# Redeploy; type and check whether "✗ probe comment" shows on the first candidate
```

S7: under spike_fluid, type a 30+ character Chinese draft (without pressing
Enter) in **Terminal, WeChat, Slack and Chrome's address bar** in turn. Record
whether the preedit renders fully, flickers, truncates, or misplaces the cursor.
One table row per application in the report.

- [ ] **Step 7: S11 + S13 — the Enter → preview → Enter loop, then a blocking Enter**

The design's core loop with a fake translation and no backend. Design §15.3
derives that it does not close as §6.1–§6.2 are written; this is the
measurement. The probe mirrors §6.1 — draft and snapshot both come from
`get_commit_text()` — and logs every key, so the log shows what the staleness
comparison saw.

```bash
cat > ~/Library/Rime/lua/spike_loop.lua <<'EOF'
-- Processor. Enter -> fake translation shown -> Enter commits it.
local MODE  = "candidate"  -- "candidate" (design §6.2) | "prompt" (design §15.2 F9)
local SLEEP = 0            -- S13: seconds to block on the translating Enter
local FAKE  = "FAKE ENGLISH"
local function log(msg)
  local f = io.open(os.getenv("HOME") .. "/spike.log", "a")
  if f then f:write(os.date("%H:%M:%S "), msg, "\n"); f:close() end
end
return function(key, env)
  local ctx = env.engine.context
  local rel = key.release                      -- method or field: Step 3 says which
  if type(rel) == "function" then rel = key:release() end
  if rel then return 2 end
  local draft = ctx:get_commit_text() or ""
  local phase = ctx:get_property("spike.phase") or ""
  local snap  = ctx:get_property("spike.snap") or ""
  log(("P key=0x%x mod=0x%x phase=[%s] draft=[%s] snap=[%s] input=[%s]")
      :format(key.keycode, key.modifier, phase, draft, snap, ctx.input))
  if key.keycode ~= 0xFF0D or draft == "" then return 2 end
  if key.modifier ~= 0 then
    log("P Enter with modifiers: passed through")  -- the Caps Lock case, R15
    return 2
  end
  if phase == "result" and draft == snap then
    env.engine:commit_text(FAKE)
    ctx:set_property("spike.phase", ""); ctx:set_property("spike.snap", "")
    ctx:clear()
    log("P -> committed the fake translation")
    return 1
  end
  if phase == "result" then log("P -> STALE on Enter: the design would re-translate") end
  if SLEEP > 0 then os.execute("sleep " .. SLEEP) end
  ctx:set_property("spike.mode", MODE)
  ctx:set_property("spike.phase", "result")
  ctx:set_property("spike.snap", draft)
  if MODE == "prompt" then
    local ok, err = pcall(function() ctx.composition:back().prompt = "  -> " .. FAKE end)
    log("P set segment.prompt: " .. tostring(ok) .. " " .. tostring(err))
  else
    ctx:refresh_non_confirmed_composition()
  end
  return 1
end
EOF
cat > ~/Library/Rime/lua/spike_loop_tr.lua <<'EOF'
-- Translator. Yields the fake candidate WITHOUT the staleness check, and logs
-- what that check would have read at this moment.
local function log(msg)
  local f = io.open(os.getenv("HOME") .. "/spike.log", "a")
  if f then f:write(os.date("%H:%M:%S "), msg, "\n"); f:close() end
end
return function(input, seg, env)
  local ctx = env.engine.context
  if (ctx:get_property("spike.phase") or "") ~= "result" then return end
  log(("T input=[%s] seg=[%d,%d) commit_text_now=[%s] snap=[%s]")
      :format(input, seg.start, seg._end, ctx:get_commit_text() or "",
              ctx:get_property("spike.snap") or ""))
  if ctx:get_property("spike.mode") ~= "candidate" then return end
  yield(Candidate("spike", seg.start, seg._end, "FAKE ENGLISH", "probe"))
end
EOF
python3 - <<'PY'
import io,os
p=os.path.expanduser("~/Library/Rime/spike_fluid.schema.yaml")
s=io.open(p,encoding="utf-8").read()
s=s.replace("\n    - lua_filter@spike_probe","")            # drop Step 6's filter
s=s.replace("processors:","processors:\n    - lua_processor@spike_loop",1)
s=s.replace("translators:","translators:\n    - lua_translator@spike_loop_tr",1)
io.open(p,"w",encoding="utf-8").write(s)
PY
# Redeploy; switch to spike_fluid (Step 5's hotkey, or Ctrl+` if S5 failed);
# open TextEdit; empty the log with:  : > ~/spike.log
```

Two starting states, each run under `MODE = "candidate"` and again under
`MODE = "prompt"` (edit the constant, Redeploy):

- **State A** — type `jintianyoudianlei`, space to confirm. The whole draft is
  confirmed. Then Enter.
- **State B** — the same, then type `buguo` and leave it unconfirmed, candidates
  showing. Then Enter.

| # | Observe | Record |
|---|---|---|
| 1 | After the first Enter | Is `FAKE ENGLISH` visible at all? Where — candidate window (which position) or inline in the preedit? |
| 2 | The second Enter | Does exactly `FAKE ENGLISH` land in TextEdit with no Chinese left behind — or does the log say `STALE on Enter`? |
| 3 | The `T` line in the log | Does `commit_text_now` equal `snap`? If not, design §6.2's third check would have suppressed the candidate |
| 4 | `candidate` only: click `FAKE ENGLISH` with the mouse | What happens to the draft? |
| 5 | `prompt` only: once the prompt shows, type one letter; separately, press Esc | Does the prompt vanish? What is left of the draft? |
| 6 | Caps Lock on, then Enter on a non-empty draft | The `mod=` value in the log, and what happens in the application (R15) |

- **S11 passes** = for at least one `MODE`, in **both** states, the translation
  is visible after the first Enter and the second Enter commits exactly it.
  Record the passing `MODE` under "constants later tasks need": Tasks 7 and 9
  build on it, and design §6.1–§6.2 are rewritten to match (decision D1).
- **S11 fails** = neither `MODE` closes the loop in both states. Stop before
  Task 7 and take §6 back to design review. Do not invent a third mechanism
  inside the spike.

**S13** — the same probe, now blocking. Set `MODE` to whichever closed the loop,
`SLEEP = 1.5`, Redeploy. In **WeChat** (the File Transfer chat), **Slack** (a DM
to yourself) and **Terminal**: type a sentence, press Enter, and type five
letters during the stall. Repeat with `SLEEP = 4`.

| Observe | Record |
|---|---|
| Did Enter reach the application — message sent, newline inserted? | per application, per duration |
| Are all five letters present afterwards, in order? | yes / no |
| Anything else: beachball, the input source switching by itself, Squirrel restarting | what was seen |

- Enter reaches the application at 1.5 s → the synchronous model does not stand
  as designed. Stop and report; P1 is then no longer a latency question.
- Only at 4 s → record the threshold; the cloud `timeout_ms` ceiling must sit
  below it.

- [ ] **Step 8: S12 + S14 — focus loss, and typing mixed content into the draft**

No new code; leave the Step 7 probe in place, because its `P` lines log the
draft on every key.

**S12** — with a 30+ character draft open and unconfirmed by Enter, in
**TextEdit** and again in **WeChat**:

| Action | Record what lands in the box, and whether the draft is still editable |
|---|---|
| Cmd+Tab to another application, then back | |
| Click at another position inside the same text box | |
| Click into a different window's text field | |
| Switch the input source to ABC and back | |

Expected from source (design §15.2 F11): the raw key string — pinyin letters —
is committed and the Chinese draft is gone. This is not pass/fail. It is the
evidence decision D2 needs (design §12 R11): write down exactly what was seen.

**S14** — inside a draft, after a confirmed Chinese segment, type each of these
and read the `draft=[…]` value from the log:

| Input | Record |
|---|---|
| `handleSubmit` — a capital in the middle, via Shift | what the composition shows; what `draft` holds |
| `https://example.com/docs` | same — `:` `/` `.` are all punctuation keys |
| an emoji through the system picker (Ctrl+Cmd+Space) | does the draft survive the picker opening, and does the emoji arrive at all |

Record only. It feeds design §12 R13 and decides whether design §10.4's
identifier, URL and emoji categories are reachable from a keyboard at all.

- [ ] **Step 9: S8 — backend latency baseline**

```bash
# Backend A: apfel
apfel serve --port 11434 &
# Backend B: translate (build from source; the model download is a one-off
#   through System Settings -> Language & Region -> Translation Languages)
#   git clone https://github.com/Arthur-Ficial/translate && cd translate && make install
#   translate --serve --port 8989 &

mkdir -p /tmp/ime_spike
cat > /tmp/ime_spike/bench.sh <<'EOF'
#!/bin/bash
# usage: bench.sh <label> <curl command template, @TEXT@ as placeholder>
label="$1"; shift
sentences=("收到，我马上看" "哈哈哈可以，就这么定了" "这个 bug 在 handleSubmit 里" \
           "文档见 https://example.com/docs" "今天有点累，不过进展不错 🎉")
for i in 1 2 3; do
  for s in "${sentences[@]}"; do
    start=$(python3 -c 'import time;print(int(time.time()*1000))')
    out=$(eval "${*//@TEXT@/$s}")
    end=$(python3 -c 'import time;print(int(time.time()*1000))')
    echo "$label round$i $((end-start))ms | $s | $out"
  done
done
EOF
chmod +x /tmp/ime_spike/bench.sh
```

(The sentences stay Chinese: they are the input under test.)

Record the **first cold call** (service just started), the warm P50/P95, and the
actual translation text for every sentence. Cold and warm must be recorded
separately. Criterion: local P95 ≤ 800 ms → the synchronous blocking route
holds and `timeout_ms` stays 1500; P95 > 1500 ms → propose adjusting
`timeout_ms` in the report, or reconsider going async.

- [ ] **Step 10: Clean up and write the report**

```bash
rm -f ~/Library/Rime/spike_fluid.schema.yaml ~/Library/Rime/lua/spike_probe.lua
rm -f ~/Library/Rime/lua/spike_loop.lua ~/Library/Rime/lua/spike_loop_tr.lua
rm -rf ~/Library/Rime/lua/spike_pkg ~/Library/Rime/default.custom.yaml
rm -f ~/Library/Rime/luna_pinyin.custom.yaml ~/spike.log
# Redeploy, confirm the IME is back to a clean state
```

Skeleton for `docs/spike-report.md`:

```markdown
# Phase 0 spike report (Plan A′)

## Environment
Squirrel / librime / librime-lua versions; macOS version

## Verdict summary
| # | Check | Verdict | Consequence |
|---|---|---|---|
| S1 | fluid_editor does not auto-commit | pass/fail | life-or-death |
| S2 | punctuation merges into the composition | pass/fail | fail → enable design §5.3 fallback |
| S2b | the §5.3 fallback (plain string values) keeps the mark in the draft | pass/fail | fail → design §5.3 back to review |
| S3 | engine:commit_text commits arbitrary text | pass/fail | life-or-death |
| S4 | ctx property read/write | pass/fail | fail → session.lua takes the downgrade path |
| S5 | key_binder select: switches both ways | pass/fail | fail → fall back to Ctrl+` |
| S6 | ShadowCandidate comment change | pass/fail | decides how the filter is written |
| S7 | long preedit per application | per app | broken ones downgrade to a floating preedit |
| S8 | backend latency baseline | P50/P95 | decides the default backend and timeout_ms |
| S9 | io.popen running curl | pass/fail | prerequisite |
| S10 | multi-file require | pass/fail | prerequisite |
| S11 | Enter → preview → Enter loop closes, states A and B | per MODE × state | neither MODE → design §6 back to review before Task 7 |
| S12 | what lands on focus loss | per app × action | evidence for decision D2 |
| S13 | Enter during a 1.5 s / 4 s stall | per app × duration | reaches the app at 1.5 s → synchronous model does not stand |
| S14 | mixed content typable into the draft | per input | feeds design §12 R13 and the §10.4 categories |

## Expected vs seen
For S1, S2, S5 and S11, design §15 states what upstream source predicts. One
line each: did the machine agree? Where it did not, which version explains it?

## Constants later tasks need
- kNoop / kAccepted values:
- KeyEvent release: method or field:
- Do Context properties survive ctx:clear():
- The libretranslate response's translation field name:
- Display mechanism that closed the S11 loop (candidate / prompt / neither):
- Enter's modifier value with Caps Lock on, and where that Enter went:

## Per-check records
(raw logs and observations)
```

- [ ] **Step 11: Record the verdict and commit**

```bash
./scripts/progress.sh gate pass      # or: gate fail
git add docs/spike-report.md
git commit -m "docs: Phase 0 spike report with the S1-S14 verdicts"
```

`gate pass` unlocks `rime/` and `tests/` for Tasks 2–12. `gate fail` keeps them
locked — which is the correct behaviour, not something to work around.

> **The recorded gate is S1/S3/S11** (decision D3, design §13). `gate pass`
> requires all three. If S1 and S3 pass but S11 fails, the gate still fails —
> unlocking `rime/` for a core loop known not to close is the quiet carry-on
> that design §3.5 forbids. S13 is not a gate item, but if it shows Enter
> reaching the application at 1.5 s the synchronous model itself is in question:
> **report to the user before running `gate pass`**, whatever S1/S3/S11 said.

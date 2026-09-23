# Issue: `/` with a draft open seemed to drop the draft

- **Status**: wontfix
- **Opened**: 2026-09-23
- **Affects**: the agent's key driver, not the IME. Found during feature 005's
  smoke run, in TextEdit, in the translation schema.

## Symptom

Observed by the agent, not by the user. Keys went to TextEdit, frontmost, as
AppleScript System Events `keystroke`, and each state was read back with
`get text of document 1`:

| Step | Keys | Read back |
|---|---|---|
| 1 | `kanyixia`, then Space (`key code 49`) | draft `看一下` |
| 2 | `keystroke "https"` | `看一下h t t p s` |
| 3 | `keystroke ":"` | `看一下合同谈判撒：`, still a draft |
| 4 | `keystroke "/"` | the draft gone; only `/` in the document |

A focus loss later committed no raw input, so the composition really was
empty after step 4: the draft was not merely hidden. The shortest repro was
step 1 then `keystroke "/"`. If a user could produce this with a key, it would
break "never eat text" (design §6.3).

## Investigation

1. **The processor.** For `/` in the idle phase, `decide` returns `noop`
   (`rime/lua/ime_translate/decide.lua`: no Enter, Space or Esc, and the phase
   is idle), so the key goes to the rest of the chain. Feature 005 changed
   nothing on that path. Ruled out.
2. **The punctuator** (librime 1.16.0 `src/rime/gear/punctuator.cc:94-132`,
   read from GitHub). For a list-valued mark it pushes the key and waits for a
   selection. None of its branches clears the composition. `:102` returns
   `kNoop` when `ascii_punct` is on.
3. **The schema's `half_shape`.** One theory was that the schema's own
   `half_shape` map replaced the imported `symbols` preset rather than merging
   with it. The compiled `~/Library/Rime/build/luna_pinyin_translate.schema.yaml`
   has 32 entries, with `"/": ["、", "､", "/", "／", "÷"]`. **Ruled out.**
4. **`ascii_punct`.** It has `reset: 0` and is not in `user.yaml`, and `,`
   after the same draft gave `看一下，` in the draft. **Ruled out.**
5. **`key_binder`.** The only slash binding is `Control+slash`. **Ruled out.**
6. **The recognizer** (`recognizer.cc:84-102`). The `punct` pattern
   `^/([0-9]0?|[A-Za-z]+)$` needs a character after the `/`, and none of the
   default patterns matches a lone `/`. **Ruled out.**
7. **The deciding control.** In the stock `luna_pinyin_simp`, a lone
   `keystroke "/"` also came out as a plain `/`: no candidate, and Esc did not
   remove it. By its config it should have opened `、`. The same key sent as
   the physical key, `key code 44`, gave `、` in the stock schema. In the
   translation schema, `看一下` then `key code 44` gave `看一下、`: the draft
   was kept and a new segment was added. **So the cause is the test driver.**
   - AppleScript's `keystroke "/"` did not deliver a key event that Rime
     recognises as the slash key while Squirrel was the input source.
   - Rime returned not-handled, and the character went to TextEdit, which
     replaced the marked text with it.
   - Why `keystroke ":"` still arrived correctly was not investigated.

## Resolution

`wontfix`: the IME does not drop the draft on a real `/`. The loss came from
the agent's synthetic key, which no physical keyboard produces.

What follows from it:
- **Drive punctuation with `key code`, not `keystroke`,** when testing the
  IME. A `keystroke` of a non-letter may never reach Rime as that key. Any
  earlier agent-observed result that typed punctuation through `keystroke`
  should be treated with that in mind.
- **Not verified:** whether a key Rime genuinely does not handle, reaching the
  application while a draft is open, can replace the marked text the same way.
  Tools that type through synthetic Unicode events, such as text expanders or
  remote-desktop clients, could produce one. No such case has been seen from a
  physical keyboard.

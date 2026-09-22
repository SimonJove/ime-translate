# Hotfix: the openai adapter sent a request body that is not JSON

- **Severity**: high
- **Date**: 2026-09-22

## Incident

Found on 2026-09-22 while preparing the configuration for a cloud GLM backend,
which is reached through the openai adapter. The adapter's request body closed
the user message with `]}]`. Every OpenAI-compatible backend therefore got
invalid JSON: OpenAI, Ollama, and GLM.
- **What it would have cost.** Every Enter with such a backend configured
  would have shown `✗` and an HTTP error. The second Enter would have committed
  the Chinese draft.
- **What it did not cost.** No red line was crossed: nothing was eaten, and
  nothing was sent.
- **Who noticed.** Nobody had configured such a backend yet. The default,
  `translate`, uses the libretranslate adapter and was not affected.

## Root cause

`rime/lua/ime_translate/backend.lua:51`, in `M.adapters.openai.body`:

```lua
']}], "temperature": ', decimal2(s.temperature), '}',
```

After the user message's content, `]}]` closes an array that is not open, and
only then the object and the `messages` array. The body read
`…"content": "你好"]}], "temperature": 0.20}`.

It was there from the adapter's first commit (feature 001, Task 6).

## Fix

The stray `]` is removed, so the fragment reads `'}], "temperature": '`. The
body is now `…"content": "你好"}], "temperature": 0.20}`. It is the one-byte
fix: the rest of the body was already right, and the anthropic and
libretranslate bodies were already valid.

## Verification

`tests/test_backend.lua` gains a section that decodes each adapter's body
with the project's own `json.decode`. For libretranslate, `q` must come back as
the draft exactly. For openai and anthropic, `model` must match, and so must
the last message: its role is the user's, and its content is the draft
exactly. The draft includes quotes, a newline, a backslash and a tab.
- **Before the fix:** `#127 openai: the request body is valid JSON (expect ,
  or } at 416)`.
- **After:** `test_backend: 136 assertions OK`, and every test file passes.
- **The mutation** (adding a bracket back) fails at #127.
- **Cross-checked** with Python's `json.loads`.

Not yet verified against a real OpenAI-compatible server. The first live call
will be the user's GLM configuration.

## Prevention

**The review gate should have caught it, and its rubric had no dimension for
it.**
- **What the tests did.** They asserted substrings of the curl command:
  `"temperature": 0.2`, the escaped quote, the escaped newline. An invalid body
  contains every one of them. Review dimension 6 ("can the test actually
  fail?") asks about tests with no teeth, but not about a structured payload
  checked only by substring.
- **Nothing downstream caught it either.** The adapter never met a real
  server. apfel was unavailable (D4), so the spike's S8 and every smoke run
  used `translate`, through the libretranslate adapter.

Added to `.claude/skills/task-review/SKILL.md`, dimension 6:
- a structured payload checked only by substring
- a code path that never runs against its real counterpart is unverified,
  however green its unit tests are

The decoding test itself stays in `tests/test_backend.lua` for every adapter.

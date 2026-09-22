# Requirements

Part of the design set — start at [overview.md](overview.md).

## 1. Background and goal

The user types Chinese day to day, but in English contexts (chat, email, code
comments) needs what they typed to become English before sending. The goal is a
real-time Chinese→English translation layer embedded in the input method: type
Chinese, and what commits to the application is the English translation.
Translation happens locally by default; the contract is in
[backend.md §7](backend.md).

**Hard constraint that decides the shape of everything:** macOS exposes no
extension API for system input methods, so Apple Pinyin cannot be extended. To
intervene at typing time across every application, a third-party IME is the
only path.

## 2. Requirements (settled)

| Dimension | Decision |
|---|---|
| Coverage | Everywhere: native apps, third-party chat (WeChat/Slack and other Electron), browser inputs, terminal/IDE |
| Interaction model | **A separate input schema**, not a mode toggle: `Ctrl+Shift+T` switches between the normal and translation schemas; the candidate window previews the translation; **the user always presses send themselves** |
| Typing habits | **Not narrowed**: segment-by-segment selection and punctuation stay normal. The IME accumulates the whole Chinese sentence itself and commits to the application exactly once, when the user confirms |
| Draft visibility | **Inline preedit inside the application's own input box** (Squirrel `inline_preedit` on). How a long draft behaves in terminals and Electron apps is the number-one compatibility item to verify |
| IME foundation | Willing to give up Apple Pinyin and switch daily driving to a Rime/Squirrel-based IME |
| Latency | Zero added cost per keystroke; Enter-to-translation P95 ≤ 800 ms locally (see [backend.md §8.2](backend.md)) |
| Backend | Pluggable protocol (adapters, [backend.md §7](backend.md)): local is the default tier, cloud APIs require an explicit opt-in. **The default is `translate`**, the local NMT behind the libretranslate adapter ([backend.md §7.5](backend.md)) — decision D4, after apfel proved unavailable on the development machine. Evaluated in 001 Task 11 ([compat-matrix.md](../compat-matrix.md)): 21 of 30 sentences acceptable — chat 7/8, code 5/6, url 1/5, emoji 3/5, mixed 5/6 — P50 20 ms, P95 37 ms, with later runs up to P95 about 150 ms. The default stands. The known weakness is URLs, whose surrounding spaces are lost |
| Distribution | Personal use. Not shipped, not notarized |

### Explicit non-goals for v1

English→Chinese reverse translation · automatically pressing send · switching
by conversation partner · cross-device sync · sentence-splitting for very long
text · **pre-translation** (interface reserved, see
[backend.md §8.3](backend.md)).

# Task 11: README, compatibility matrix and quality evaluation

> **Revised 2026-09-22, before this task started** (decisions.md, "001 Task 11
> revised before start"). By the user's decisions:
> - The eval measures `translate` alone. apfel cannot run on this machine
>   (D4), and `translate` stays the default.
> - The agent writes the 18 sentences the set still needed, marked as
>   composed, not taken from real chat.
> - The agent drives and observes the compatibility matrix, and the user
>   confirms it.
> - The matrix covers TextEdit, Chrome, Safari, WeChat (the File Transfer
>   chat), Terminal, a second terminal app, Messages and Notes.
>
> The README also covers feature 002, the mixed input.

**Files:**
- Create: `README.md`, `docs/compat-matrix.md`, `eval/sentences.txt`,
  `scripts/eval.sh`, `eval/results-translate.md`
- Modify: `docs/design/architecture.md` §2 (the backend row: the eval's
  conclusion)

**Interfaces:**
- Consumes: the IME installed by 001 Task 10 and 002 Task 5; the `translate`
  service on `127.0.0.1:8989`
- Produces: the user documentation, the compatibility evidence, and the
  evaluation of the default backend

**Who observes.** The agent drives the machine as in 001 Task 10:
- plain keys through System Events
- modified keys as CoreGraphics events
- a window screenshot only after checking it is frontmost
- the document's text read back over AppleScript

Each cell says "agent". The user reviews the matrix and confirms it. A check
that needs a physical Shift tap is not in the matrix; 002 Task 6 covered it in
TextEdit.

Private content stays private:
- **Notes.** A temporary note is created, read back over AppleScript, and
  deleted. Notes is never screenshotted, since its sidebar lists the user's
  notes.
- **Messages.** Tests happen only in a new message with no recipient. No
  conversation is opened.
- **WeChat.** Only the File Transfer chat, its title checked first. Send is
  never pressed.
- **The terminals.** Tests happen inside `cat > /dev/null`, so no Enter runs a
  command. The process is ended with Control+C afterwards.

- [ ] **Step 1: README**

`README.md` covers:
- **Installing:** the two brew installs, `./scripts/install.sh`, adding
  Squirrel in System Settings, the model download for `translate`, and the
  restart after installing.
- **Switching schemas:** `Ctrl+Shift+T` in and out.
- **Keys in the translation schema:**
  - Enter translates, and Enter again commits.
  - Shift+Enter commits the Chinese.
  - Esc drops the translation and keeps the draft.
- **Mixed input, feature 002:**
  - Enter on unselected pinyin keeps it as English letters.
  - Space with nothing unselected adds a space.
  - A Shift tap switches to English mode.
  - Caps Lock only types capitals.
  - Select the Chinese before Enter translates.
- **The config file** `~/Library/Rime/ime_translate.yaml` and its keys.
- **The cloud backend and its two costs:** privacy, and a 0.5–2 s freeze on
  every Enter. `allow_remote`, and the Keychain command with `-w` last.
- **The log** at `~/Library/Logs/ime_translate.log`. It is off by default and
  holds what you type while on.
- **Known limits:** focus loss commits the raw pinyin (D2), the schema a new
  session starts in (D6), and a user dictionary that does not learn (R13).
- **Uninstalling:** the files `install.sh` wrote, the LaunchAgent, and
  `rime.lua`'s binding line.

- [ ] **Step 2: Compatibility matrix**

`docs/compat-matrix.md` crosses eight applications with seven checks.

The applications:
- TextEdit
- Chrome, on a local blank page with a `<textarea>`
- Safari, on the same page
- WeChat, the File Transfer chat
- Terminal and a second terminal app, both inside `cat > /dev/null`
- Messages, in a new message with no recipient
- Notes, in a temporary note

| Check | Keys | Supported when |
|---|---|---|
| C1 translate and commit | `jintianyoudianlei`␣ ⏎ ⏎ | The English commits; no Chinese residue; nothing sent or run |
| C2 the Enter way | `jintian`␣ `readme`⏎ `haode`␣ ⏎ ⏎ | The English keeps `readme` |
| C3 Shift+Enter | `jintian`␣, Shift+Enter | `今天` commits, untranslated |
| C4 Esc on the prompt | `jintianyoudianlei`␣ ⏎, Esc | The prompt goes; the draft stays |
| C5 the display | during C1 | Record where the preedit and the prompt show: inline, or in the candidate window (`no_inline`) |
| C6 focus loss | `jintian`, then switch to another app and back | Record what lands (D2: raw pinyin) |
| C7 the starting mode | the first key in a new input box | Record whether the schema starts in Chinese, or in English by `app_options` (F24) |

Every cell is **supported**, **needs config** (say which), or **unverified**
(say why); none is blank. Slack, Notion and Gmail as web apps, iMessage as a
conversation, and VS Code are not installed or not used. They get one row each,
marked unverified.

- [ ] **Step 3: Evaluation sentence set and script**

`eval/sentences.txt` holds one sentence per line as `category<TAB>sentence`.
There are 30: 8 chat, 6 code, 5 url, 5 emoji and 6 mixed. The first 12 come
from the original plan. The other 18 were composed by the agent, by the user's
decision, and are not from real chat. The user may swap in real ones at any
time.

```
chat	收到，我马上看
chat	哈哈哈可以，就这么定了
chat	这个我先放着，明天再说吧
chat	行吧那你看着办
chat	稍等一下我这边还在开会
code	这个 bug 在 handleSubmit 里，参数没传对
code	你把 user_id 和 created_at 一起加到索引里
url	文档见 https://example.com/docs，第三节讲的就是这个
url	帮我看下 https://github.com/foo/bar/pull/42 这个 PR
emoji	今天有点累，不过进展不错 🎉
emoji	搞定了 🚀 明天可以上线
emoji	辛苦了！先下班吧 🙏
chat	我晚点再回你，现在在路上
chat	这个方案我觉得还行，就是有点赶
chat	周末有空一起吃个饭吗
code	把 config.yaml 里的 timeout_ms 改成 3000 试试
code	这个接口返回 404，应该是路由写错了
code	跑一下 npm run build 看看有没有报错
code	getUserById 返回的是 null，你查一下缓存
url	我把设计稿放在 https://www.figma.com/file/abc123 了
url	会议链接：https://meet.google.com/xyz-abcd-efg
url	参考这篇 https://en.wikipedia.org/wiki/Machine_translation
emoji	生日快乐 🎂 今天玩得开心
emoji	太强了 👍👍
mixed	今天的 standup 改到下午三点
mixed	这个 feature 下周一 release
mixed	帮我 review 一下这个 PR
mixed	我们用 Redis 做缓存吧
mixed	周五之前把 README 更新一下
mixed	这个 bug 我已经 fix 了，你 pull 一下
```

`scripts/eval.sh` sends each sentence exactly as the IME's libretranslate
adapter does (`/translate`, `source: zh`, `target: en`, `format: text`), so the
text under test takes the user's path from the draft onward:

```bash
#!/bin/bash
# Evaluate the default backend, translate (the libretranslate adapter), on
# eval/sentences.txt: one request per sentence, as the IME sends it; the
# translation and the time; then P50 and P95 (nearest rank).
# usage: scripts/eval.sh [base_url]      default http://127.0.0.1:8989
set -euo pipefail
cd "$(dirname "$0")/.."
BASE="${1:-http://127.0.0.1:8989}"
OUT="eval/results-translate.md"
python3 - "$BASE" "$OUT" <<'PY'
import json, math, sys, time, urllib.request
base, out = sys.argv[1], sys.argv[2]
rows, times = [], []
for line in open("eval/sentences.txt", encoding="utf-8"):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    cat, src = line.split("\t", 1)
    body = json.dumps({"q": src, "source": "zh", "target": "en", "format": "text"}).encode()
    req = urllib.request.Request(base + "/translate", data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            text = json.load(r).get("translatedText", "")
    except Exception as e:
        text = "ERROR " + type(e).__name__
    ms = round((time.monotonic() - t0) * 1000)
    rows.append((cat, src, text, ms))
    times.append(ms)
def pct(p):
    s = sorted(times)
    return s[max(0, math.ceil(p / 100 * len(s)) - 1)]
cell = lambda s: s.replace("|", "\\|").replace("\n", " ")
with open(out, "w", encoding="utf-8") as f:
    f.write(f"# Evaluation: translate ({base})\n\n")
    f.write("| # | category | source | translation | ms | verdict |\n")
    f.write("|---|---|---|---|---|---|\n")
    for i, (cat, src, text, ms) in enumerate(rows, 1):
        f.write(f"| {i} | {cat} | {cell(src)} | {cell(text)} | {ms} | |\n")
    f.write(f"\n{len(times)} sentences. P50 {pct(50)} ms, P95 {pct(95)} ms.\n")
print(f"wrote {out}: {len(times)} sentences, P50 {pct(50)} ms, P95 {pct(95)} ms")
PY
```

```bash
chmod +x scripts/eval.sh
```

- [ ] **Step 4: Run the eval and judge it**

```bash
./scripts/eval.sh
```

Expected: `wrote eval/results-translate.md: 30 sentences, P50 … ms, P95 … ms`,
with no `ERROR` row.

In the `verdict` column, the agent marks each translation **acceptable** or
**not**, with a few words on why. Things to note:
- a lost or damaged URL, code identifier or emoji
- a dropped English word in a mixed sentence
- tone: R4, NMT skews formal

The user reviews the verdicts. The conclusion then goes at the end of
`docs/compat-matrix.md`, and into design §2's backend row: the acceptable
share by category, P50/P95, and whether `translate` stays the default (D4) or a
decision should be opened.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/compat-matrix.md eval/ scripts/eval.sh docs/design/architecture.md
git commit -m "docs: README, compatibility matrix and translate evaluation"
```

# Compatibility matrix and the backend evaluation

Feature 001, Task 11 (plan: [`task-11-eval.md`](features/001-zh-en-ime/plan/task-11-eval.md)).
Build `2c37552` and later: features 001 and 002 installed, `translate` as the
backend.

**How it was observed** (2026-09-22). By the user's decision, the agent drove
the machine, and the user confirmed the result the same day.
- **Keys.** Plain keys went through System Events. Modified keys went as
  CoreGraphics events.
- **Screenshots.** Only a window's content, and only after checking it was
  frontmost.
  - None showed a private application's content.
  - One exception: a thin strip across the top of WeChat's chat pane, taken
    to check which chat was open. It showed no title, and the file was
    deleted afterwards.
- **Readback.**
  - TextEdit and Notes over AppleScript
  - the browsers through the clipboard, saved first and restored after
  - Terminal through the file `cat` wrote to
- **Cells from earlier runs** say so:
  - 001 Task 10 smoke rows 27–28, agent-observed and accepted by the user
  - 002 Task 6, confirmed by the user as a whole

**Where the Enter keys went.** In a chat or a terminal, no Enter was left to
the application:
- In WeChat, the IME took both Enters.
- In Terminal, the checks ran inside `cat > file`, so nothing was run.

## The checks

| Check | Keys | Supported when |
|---|---|---|
| C1 translate and commit | `jintianyoudianlei`␣ ⏎ ⏎ | The English commits; no Chinese residue; **nothing sent or run** by either Enter (design §2: send is always manual) |
| C2 the Enter way | `jintian`␣ `readme`⏎ `haode`␣ ⏎ ⏎ | The English keeps `readme` |
| C3 Shift+Enter | `jintian`␣, Shift+Enter | `今天` commits, untranslated |
| C4 Esc on the prompt | `jintianyoudianlei`␣ ⏎, Esc | The prompt goes, the draft stays. Shown by a Shift+Enter afterwards committing `今天有点累` |
| C5 the display | during C1 | Where the preedit and the prompt show |
| C6 focus loss | `jintian`, another app, back | What was typed lands in the field, raw, and nothing is lost. That is D2's documented cost, and the cell records what landed |
| C7 the starting mode | the first key in a new field | A new field starts in Chinese. **Needs config** when `app_options` start it in English (F24) |

## The matrix

| Application | C1 | C2 | C3 | C4 | C5 | C6 | C7 |
|---|---|---|---|---|---|---|---|
| TextEdit | supported | supported | supported | supported | supported: inline, prompt after the draft | supported: `jintian`, raw pinyin | supported: Chinese |
| Chrome, local page `<textarea>` | supported | supported | supported | supported | supported: inline, prompt after the draft | supported: `jin tian`, the preedit with its spaces; the user may judge otherwise | supported: Chinese |
| Safari, local page `<textarea>` | supported | supported | supported | supported | supported: inline, prompt after the draft | supported: `jintian` | supported: Chinese |
| Safari, address bar (by accident; kept as a record) | supported | supported | supported | supported | supported: inline in the field | supported: `jintian` | supported: Chinese |
| WeChat, File Transfer chat | supported (001 row 27) | supported (002 row 45, user) | unverified | supported (001 row 28) | supported: inline, underlined (001 row 27) | unverified | unverified |
| Terminal | unverified | unverified | unverified | unverified | unverified: `no_inline` puts the preedit in the candidate window (a source reading) | unverified | **needs config**: English, by `app_options` |
| A terminal hosting the agent's own session | unverified | unverified | unverified | unverified | unverified | unverified | unverified |
| Messages, a new message with no recipient | unverified | unverified | unverified | unverified | unverified | unverified | unverified |
| Notes | unverified | unverified | unverified | unverified | unverified | unverified | unverified |
| Messages, an iMessage conversation | unverified | unverified | unverified | unverified | unverified | unverified | unverified |
| Slack | unverified | unverified | unverified | unverified | unverified | unverified | unverified |
| Notion (web) | unverified | unverified | unverified | unverified | unverified | unverified | unverified |
| Gmail (web) | unverified | unverified | unverified | unverified | unverified | unverified | unverified |
| VS Code | unverified | unverified | unverified | unverified | unverified | unverified | unverified |

**Why the unverified cells are unverified:**
- **WeChat, C3, C6 and C7.** The agent could not confirm, without a wider
  screenshot of a private window, that the open chat was File Transfer. It
  typed nothing into WeChat.
- **Terminal.** Squirrel's `app_options` start `com.apple.Terminal` with
  `ascii_mode: true` and `no_inline: true`. The agent's posted
  `Control+Shift+2` reached the terminal as `^@` and did not switch to
  Chinese, so every check ran as plain letters. A physical Shift tap (feature
  002) switches it.
- **The terminal hosting the agent's own session** was not used: the agent
  does not type into its own session.
- **Messages and Notes.** Not run to the end.
  - In Notes the focus probe showed that keys were not reaching the note
    body, and the run stopped there (see Findings).
  - Messages was not started: not a new message, and not an iMessage
    conversation.
- **Slack, Notion, Gmail and VS Code** are not installed, or not used. The
  browser `<textarea>` rows cover a plain web text field only. The web apps
  have their own editors, which were not tried.

**Needs config: Terminal.** Squirrel starts it in English. Tap Shift once in a
new Terminal window, or drop `com.apple.Terminal` from `app_options` in
`~/Library/Rime/squirrel.custom.yaml`.

## Findings

- **Focus loss (D2)** commits what the field shows as raw input. In Chrome
  that is the preedit with its syllable spaces (`jin tian`); elsewhere it is
  the raw keys.
- **The input source can be per window.** A new Safari window kept ABC until
  Squirrel was selected in it. The first Safari run typed plain letters, and it
  was discarded.
- **Automation in private apps.** A generic select-all-and-delete "clear" is
  unsafe where focus can land on a list. The Notes run was stopped when its
  focus probe failed. The rule from here on: in a private application,
  confirm the focus first, and never select all.

## The backend evaluation: `translate`

**Where the sentences come from.** 12 come from the original plan, and their
URLs are placeholders (`example.com`, `github.com/foo/bar`). The other 18
(appendix rows 13–30) were composed by the agent on 2026-09-22, by the user's
decision. None is from the user's real chat, so 21/30 measures chat-style
text, not the user's own messages.

`scripts/eval.sh` writes the 30 sentences' results to
`eval/results-translate.md`, a runtime artifact that `.gitignore` excludes. The
run judged here, with its verdicts, is copied into the appendix below. The
sentences are sent exactly as the IME's libretranslate adapter sends them. The first run showed
that Python's `urllib` takes the macOS system proxy even for `127.0.0.1`, where
the IME's `curl` goes direct. `scripts/eval.sh` therefore bypasses the proxy.

| Category | Acceptable |
|---|---|
| chat | 7 / 8 |
| code | 5 / 6 |
| url | 1 / 5 |
| emoji | 3 / 5 |
| mixed | 5 / 6 |
| **all** | **21 / 30** |

**Latency:** P50 20 ms, P95 37 ms in the judged run. Two later runs the same
day, while `eval.sh`'s error handling was being checked, gave P50 45–49 ms and
P95 127–149 ms. Latency varies with the machine's load, and every run is far
inside design §2's 800 ms budget.

**Where it falls short:**
- **URLs.** The space around a URL is lost (`documenthttps://…`), and once the
  text after a URL stayed Chinese. This is the "lost space before URLs" noted
  when D4 closed, and it is the one systematic failure.
- **Idiom.** Some colloquial words are read literally: `太强了` as "Too
  strong", `上线` as "go online".
- **Oddities.** A stray word ("At all right"), and one sentence in all
  capitals.
- **Mixed Chinese-English sentences** did well: the English words were kept
  in 6 of 6 sentences, and 5 of 6 were acceptable.

**Conclusion.** `translate` stays the default (D4). It is fast, local, and
acceptable for chat and for mixed sentences.
- **The URL failure** is worth a fix: protect URLs around the backend call,
  and put the spaces back after. That would be a new decision, not part of
  this task.
- **A local LLM was considered** afterwards: Ollama with a ~4B model, through
  the existing `openai` adapter. The user decided to stay with `translate`
  for now and move to an LLM only if a need appears (2026-09-22).

The verdicts are the agent's. **The user confirmed the matrix and the verdicts on 2026-09-22**, Chrome's `jin tian` under C6 as supported included.

## Appendix: the evaluation run of 2026-09-22

| # | category | source | translation | ms | verdict |
|---|---|---|---|---|---|
| 1 | chat | `收到，我马上看` | `Got it. I'll read it right away.` | 46 | acceptable |
| 2 | chat | `哈哈哈可以，就这么定了` | `Hahaha, okay, that's it.` | 26 | acceptable — loose: 'that's it' for 'settled' |
| 3 | chat | `这个我先放着，明天再说吧` | `I'll leave this for now. Let's talk about it tomorrow.` | 25 | acceptable |
| 4 | chat | `行吧那你看着办` | `At all right, it's up to you.` | 22 | not — a stray 'At' opens the sentence |
| 5 | chat | `稍等一下我这边还在开会` | `Wait a minute. I'm still in a meeting.` | 19 | acceptable |
| 6 | code | `这个 bug 在 handleSubmit 里，参数没传对` | `This bug is in handleSubmit, and the parameters are not passed correctly.` | 28 | acceptable |
| 7 | code | `你把 user_id 和 created_at 一起加到索引里` | `You add user_id and created_at to the index together.` | 30 | acceptable — literal: 'You add' where an imperative fits |
| 8 | url | `文档见 https://example.com/docs，第三节讲的就是这个` | `See the documenthttps://example.com/docs，第三节讲的就是这个` | 15 | not — the space before the URL is lost, and the text after it stays Chinese |
| 9 | url | `帮我看下 https://github.com/foo/bar/pull/42 这个 PR` | `Look at it for me.https://github.com/foo/bar/pull/42This PR` | 26 | not — the URL is glued to the words on both sides |
| 10 | emoji | `今天有点累，不过进展不错 🎉` | `I'm a little tired today, but it's progressing well 🎉` | 22 | acceptable |
| 11 | emoji | `搞定了 🚀 明天可以上线` | `Done 🚀 You can go online tomorrow.` | 21 | not — 'go online' misreads 'launch' |
| 12 | emoji | `辛苦了！先下班吧 🙏` | `Thank you for your hard work! Get off work first 🙏` | 26 | acceptable — stiff: 'Get off work first' |
| 13 | chat | `我晚点再回你，现在在路上` | `I'll get back to you later. I'm on my way now.` | 20 | acceptable |
| 14 | chat | `这个方案我觉得还行，就是有点赶` | `I think this plan is okay, but it's a little rushed.` | 21 | acceptable |
| 15 | chat | `周末有空一起吃个饭吗` | `Are you free to have a meal together this weekend?` | 19 | acceptable |
| 16 | code | `把 config.yaml 里的 timeout_ms 改成 3000 试试` | `Change the timeout_ms in config.yaml to 3000 and try it.` | 37 | acceptable |
| 17 | code | `这个接口返回 404，应该是路由写错了` | `This interface returns 404, which should be the wrong routing.` | 24 | not — 'which should be the wrong routing' garbles 'the route is probably wrong' |
| 18 | code | `跑一下 npm run build 看看有没有报错` | `Run npm run build to see if there is an error.` | 20 | acceptable |
| 19 | code | `getUserById 返回的是 null，你查一下缓存` | `getUserById returns null. Please check the cache.` | 24 | acceptable |
| 20 | url | `我把设计稿放在 https://www.figma.com/file/abc123 了` | `I put the design draft inhttps://www.figma.com/file/abc123It's` | 22 | not — URL glued ('inhttps'), stray 'It's' after it |
| 21 | url | `会议链接：https://meet.google.com/xyz-abcd-efg` | `Conference link:https://meet.google.com/xyz-abcd-efg` | 14 | acceptable — the URL is intact; the space after the colon is lost |
| 22 | url | `参考这篇 https://en.wikipedia.org/wiki/Machine_translation` | `Refer to this articlehttps://en.wikipedia.org/wiki/Machine_translation` | 13 | not — URL glued to 'article' |
| 23 | emoji | `生日快乐 🎂 今天玩得开心` | `Happy birthday 🎂 Have a good time today` | 15 | acceptable |
| 24 | emoji | `太强了 👍👍` | `Too strong 👍👍` | 14 | not — 'Too strong' loses 'awesome' |
| 25 | mixed | `今天的 standup 改到下午三点` | `Today's standup has been changed to 3:00 p.m.` | 18 | acceptable |
| 26 | mixed | `这个 feature 下周一 release` | `This feature will be released next Monday.` | 15 | acceptable |
| 27 | mixed | `帮我 review 一下这个 PR` | `Help me review this PR` | 14 | acceptable |
| 28 | mixed | `我们用 Redis 做缓存吧` | `Let's use Redis as a cache.` | 16 | acceptable |
| 29 | mixed | `周五之前把 README 更新一下` | `UPDATE README BEFORE FRIDAY.` | 15 | not — all capitals |
| 30 | mixed | `这个 bug 我已经 fix 了，你 pull 一下` | `I have fixed this bug. You pull it.` | 16 | acceptable — blunt: 'You pull it' |

30 sentences. P50 20 ms, P95 37 ms.

# Task 12: Wrap-up — full verification and documentation write-back

> **Revised 2026-09-22, before this task started** (decisions.md, "001 Task 12
> revised before start").
> - **The recheck.** After the clean reinstall, the agent runs the core checks
>   it can drive in TextEdit: K1–K12 below, which need no physical Shift or
>   Caps Lock. The user confirms them as a whole. This replaces "the 16 checks
>   of Task 10 Step 6"; that table grew to 28 rows, and feature 002 added more.
> - **D2 stays open.** D1 and D3 are closed; D2 is the user's decision, not
>   yet made.

**Files:**
- Modify: `docs/design/` (fold the spike verdicts and the default backend back in)

**Interfaces:**
- Consumes: every preceding task
- Produces: a daily-usable IME, plus documentation that matches the
  implementation

- [ ] **Step 1: Full unit test run**

Run: `scripts/run_tests.sh`
Expected: everything PASS, exit code 0

- [ ] **Step 2: Clean-machine reinstall verification**

```bash
shasum -a 256 "$HOME/Library/Rime/ime_translate.yaml"      # the user config, before
rm -rf "$HOME/Library/Rime/lua/ime_translate" "$HOME/Library/Rime/lua/ime_translate_"*.lua
rm -f "$HOME/Library/Rime/luna_pinyin_translate.schema.yaml"
./scripts/install.sh
./scripts/install.sh                                          # the second run changes nothing
shasum -a 256 "$HOME/Library/Rime/ime_translate.yaml"      # the user config, after: the same
# restart Squirrel (no draft open), then run K1–K12 in TextEdit
```

Confirm `install.sh` is idempotent: the second run prints no `installed` or
`bound` line, and the user config's hash is unchanged.

The core checks, in TextEdit with the translation schema. The agent drives
them as in 001 Task 10, and the user confirms them as a whole.

| # | From | Keys | Pass when |
|---|---|---|---|
| K1 | 001 rows 1, 4, 5 | `jintianyoudianlei`␣ ⏎ ⏎ | The prompt shows the English; then the English commits |
| K2 | 001 row 7 | the prompt showing, `a` | The prompt goes; `a` joins the draft |
| K3 | 001 row 9 | the prompt showing, BackSpace | The prompt goes; the draft steps back |
| K4 | 001 row 10 | the prompt showing, Esc | The prompt goes; the draft stays |
| K5 | 001 row 11 | `jintian`␣, Shift+Enter | `今天` commits |
| K6 | 001 row 12 | `base_url` pointed at a closed port, then restart; `jintian`␣ ⏎ ⏎ | `✗ 翻译服务未启动` shows; the second Enter commits `今天`; the config is restored afterwards |
| K7 | 001 rows 18–19 | `jintiantianqihenhao`, Left, ⏎ ⏎ ⏎ | The first ⏎ only moves the caret, the second locks the letters (the Enter way), and the third commits them as is |
| K8 | 002 rows 33–34 | `jintian`␣ `readme`⏎ `haode`␣ ⏎ ⏎ | The English keeps `readme` |
| K9 | 002 row 35 | `qing`␣ `pull`⏎ ␣ `request`⏎ ⏎ ⏎ | The English keeps `pull request` |
| K10 | 002 row 36 | `readme`⏎ ⏎ | `readme` commits as is, with no freeze |
| K11 | 002 row 40 | the prompt showing, ␣, then ⏎ | The prompt goes, a space joins the draft, and ⏎ translates anew |
| K12 | 002 row 47 | `jintian`␣ `readme`⏎, Shift+Space | A space joins the draft; nothing commits |

- [ ] **Step 3: Write the findings back into the design set**

Fold the spike report's actual conclusions back in:

| Target | Change |
|---|---|
| `design/requirements.md` §2, "Backend" row | Record the default backend chosen by the blind eval |
| `design/architecture.md` §5.3 | Replace the two branches with whichever one S2 actually decided; delete the unused one |
| `design/testing.md` §10.2 | Annotate each S1–S14 row with its real verdict |
| `design/architecture.md` §6.1–§6.2 | Rewrite to the display mechanism S11 selected (decision D1) and delete the two open-finding notes. If Tasks 7 and 9 were built on it, this should already have happened before Task 7 — confirm, do not redo |
| `design/upstream.md` §15 | Mark each F-row confirmed or contradicted by the spike, with the version it was seen on; correct §15.3 where the machine disagreed |
| `design/risks.md` §12 | Strike the risks that were falsified or mitigated; add any newly discovered. R10–R15 each need a measured verdict in place of "source-derived" |
| `design/decisions.md` §13 | Confirm D1 and D3 are closed with their spike evidence. D2 stays open: the user's decision |
| `design/overview.md` status line | Change "Plan A′ locked; awaiting Phase 0 spike verification" to "verified, v1 usable" |
| `design/decisions.md` §13 | Add an entry for anything the spike changed about the design |

- [ ] **Step 4: Commit**

```bash
git add docs/design/
git commit -m "docs: write back spike verdicts and the backend choice"
```

- [ ] **Step 5: Close out**

```bash
./scripts/progress.sh done 12 <hash>
./scripts/progress.sh status      # should read 12/12 done
```

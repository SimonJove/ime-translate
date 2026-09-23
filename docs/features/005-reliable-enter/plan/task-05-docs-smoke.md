# Task 5: README, template; real-machine smoke (manual)

**Files:** modify `README.md`, `rime/ime_translate.yaml`; create
`docs/smoke-report-005.md`.

- [ ] **Step 1: Docs.**
  - README key table: Enter in the error state translates again.
  - README cloud section: the fallback and its `☁✗` marker; the cap of 2000;
    "There is no automatic fallback" goes.
  - README known limits: `translate` and URLs.
  - Template: `cloud_timeout_ms` at most 2000.
- [ ] **Step 2: Install** with `./scripts/install.sh`; `./scripts/doctor.sh`.
- [ ] **Step 3: Smoke, observed by the user**, in TextEdit:
  1. Local: a sentence with a URL; the English keeps the URL, spaced.
  2. Cloud active, network cut or `cloud_base_url` pointed at an unused
     `https://` port: Enter shows `☁✗ -> …` within 2.5 s; Enter commits it.
  3. Local service stopped, local active: `✗ 翻译服务未启动`; Enter shows the
     error again, commits nothing; Shift+Enter commits the Chinese.
  4. Esc, then Enter on the same draft, cloud active: the translation shows at
     once.
- [ ] **Step 4: Commit** `docs: feature 005 in the README and template; smoke`

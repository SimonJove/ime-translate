# Task 2: Schema text, README, template; real-machine smoke (manual)

- [ ] **Step 1: Text**
  - Replace `Ctrl+Shift+B` with "a tap of Right Option" in these places:
    - the schema's description line and header note 10
    - the README's key table, "Using a large language model" and
      "Switching"
    - the config template's header
  - Add a README line on the mouse edge: Right Option held through a click and
    released within 500 ms also switches.
- [ ] **Step 2: Install** with `./scripts/install.sh`.
- [ ] **Step 3: Smoke.**
  - **The user**, in each app below, with nothing typed:
    - TextEdit
    - Chrome, on the local test page
    - a terminal, inside `cat > /dev/null`

    One Right Option tap. Passes when the notice shows, and the active file
    flips.
  - **The agent** checks:
    - `Ctrl+Shift+B` switches nothing
    - Left Option does nothing
    - Option+letter still types
    - with a draft, a tap voids the translation and keeps the draft
  - Record the results in `docs/smoke-report-004.md`.
- [ ] **Step 4: Commit** `docs: feature 004 smoke report`

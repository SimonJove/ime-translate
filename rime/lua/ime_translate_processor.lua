-- Thin glue: read the context, call the pure decide function, execute the
-- action.
-- **This file is the only place in the project allowed to call
-- engine:commit_text().**
local shared = require("ime_translate_shared")
local session = require("ime_translate.session")
local decide = require("ime_translate.decide")
local shift_tap = require("ime_translate.shift_tap")
local backend = require("ime_translate.backend")
local route = require("ime_translate.route")
local keys = require("ime_translate.keys")

local kAccepted, kNoop = 1, 2 -- confirmed by spike Task 1 Step 3; follow the report if it differs

-- Feature 003 (design §5.6): the notice switches the schema declares, one per
-- outcome of a switch. Squirrel shows the label of an option turned on; each
-- off label is empty, which keeps them out of the switcher menu and makes
-- turning one off show nothing (upstream F29).
local NOTICE = { ["local"] = "ime_translate_notice_local",
                 cloud = "ime_translate_notice_cloud",
                 none = "ime_translate_notice_no_cloud" }

local function log(S, msg)
  if S.settings and S.settings.debug_log then
    local f = io.open(os.getenv("HOME") .. "/Library/Logs/ime_translate.log", "a")
    if f then f:write(os.date("%m-%d %H:%M:%S "), msg, "\n"); f:close() end
  end
end

-- The display is the last segment's prompt (design §6.4, decision D1): shown in
-- the preedit, never read by get_commit_text(), never committed. A non-empty
-- draft means a non-empty composition, so back() is a segment.
local function show(ctx, draft)
  if draft ~= "" then ctx.composition:back().prompt = session.prompt(ctx) end
end

-- With the caret inside unconverted input the composition stops at the caret:
-- get_commit_text() holds only what lies before it, while the rest is still on
-- screen, and ctx:clear() would drop it (design §5.2, upstream F15 -- a source
-- reading). So an action that acts on the whole draft (on_draft below) only
-- moves the caret to the end, and the next key acts on the whole draft, now on
-- screen. Native Return also ends with the caret at the end, but confirms the
-- highlighted candidate first; this recomposes, so a non-default highlight
-- falls back to the default -- shown before the next press, never committed
-- unseen.
local function caret_inside(ctx) return ctx.caret_pos < #ctx.input end

-- Pass the key past one tap watcher (shift_tap) and keep its state in Context.
-- The state is written only when there is some, not on every letter.
local function watch(ctx, k, now, tap)
  local before = session.tap_down(ctx, tap)
  local down, tapped = shift_tap.observe(before, k, now, tap)
  if down or before then session.set_tap_down(ctx, tap, down) end
  return tapped
end

-- Drop a translation or an error on screen and keep the draft: back to idle,
-- and the prompt goes with the phase.
local function void(ctx, draft)
  session.clear(ctx)
  show(ctx, draft)
end

-- Design §5.6: switch the backend slot. A translation on screen is voided
-- first, as by Esc: the prompt goes, the draft stays, and the next Enter
-- translates with the other backend. Nothing is committed or cleared.
local function switch_backend(S, ctx, draft)
  void(ctx, draft)
  local now, remembered = S.switch()
  -- On, then off: set_option notifies either way, and only the on state has
  -- a label (F29). Each call refreshes an open segment, as any option change
  -- does (F20); the input is untouched.
  local notice = NOTICE[now or "none"]
  ctx:set_option(notice, true)
  ctx:set_option(notice, false)
  log(S, "switch backend: " .. (now or "no cloud slot")
         .. (remembered == false and ", not remembered" or ""))
  return kAccepted
end

-- The actions decide names (decide.lua), each run as (S, env, ctx, draft) ->
-- kAccepted or kNoop. "noop" has no entry: the key goes on to the native chain.
-- on_draft: the action reads or changes the whole draft, so the caret rule
-- above applies first.
local ACTIONS = {}

ACTIONS.translate = { on_draft = true, run = function(S, env, ctx, draft)
  -- Synchronous block, at most 2500 ms: the active slot's timeout_ms, or for
  -- the cloud its 2000 and then the local fallback's 500 (backend.md §8.2).
  -- The route picks the answer: the cache, the active slot (process-wide,
  -- design §5.6), then local for a failed cloud (feature 005, §8.1).
  local r = route.translate(S, draft, backend.real_runner)
  -- r.cloud is the §7.2 marker: decided by the URL, not by the slot's name
  if r.ok then session.set_result(ctx, draft, r.text, r.cloud, r.fallback)
  else session.set_error(ctx, draft, r.code, r.cloud) end
  -- No refresh_non_confirmed_composition(): the measured path (S11) wrote the
  -- prompt and returned, and a refresh may rebuild the segment holding it.
  show(ctx, draft)
  log(S, ("translate [%s%s] %q -> %s"):format(S.active, r.fallback and ", local fallback" or "",
                                             draft, r.ok and r.text or ("ERR " .. r.code)))
  return kAccepted
end }

ACTIONS.commit_translation = { on_draft = true, run = function(S, env, ctx, draft)
  -- Commit only a translation that is on screen. A click on the highlighted
  -- candidate confirms the segment and adds an empty one after it: the prompt
  -- vanishes while the draft stays the same, so check 2 cannot see it (Task 10
  -- smoke row 22, observed by the agent). Then this Enter shows the
  -- translation again and the next one commits it; the draft is unchanged,
  -- so no backend call.
  if ctx.composition:back().prompt ~= session.prompt(ctx) then
    show(ctx, draft)
    log(S, "translation was off screen: shown again")
    return kAccepted
  end
  -- Never eat text: commit first, clear second. Context properties survive
  -- ctx:clear(), so they must be cleared explicitly; ctx:clear() removes the
  -- segment and its prompt with it.
  env.engine:commit_text(session.text(ctx))
  session.clear(ctx)
  ctx:clear()
  log(S, "commit translation")
  return kAccepted
end }

ACTIONS.commit_draft = { on_draft = true, run = function(S, env, ctx, draft)
  env.engine:commit_text(draft)
  session.clear(ctx)
  ctx:clear()
  log(S, "commit draft")
  return kAccepted
end }

-- Esc in result/error: drop the prompt, keep the draft. Passed on, the native
-- Esc wipes the whole draft (S11 row 5b).
ACTIONS.clear_display = { run = function(S, env, ctx, draft)
  void(ctx, draft)
  return kAccepted
end }

ACTIONS.lock_literal = { on_draft = true, run = function(S, env, ctx, draft)
  -- Design §5.5: what is not yet selected becomes the letters typed. One bare
  -- segment over it, confirmed: a segment with no candidate is confirmed as
  -- raw input (upstream F20). The mode is not touched, so Squirrel shows no
  -- notice (F24). Nothing is committed or cleared.
  local comp = ctx.composition
  local segs = comp:toSegmentation()
  local start = segs:get_confirmed_position()
  ctx:clear_non_confirmed_composition()
  if comp:empty() or comp:back().start ~= start or comp:back()._end ~= start then
    segs:add_segment(Segment(start, start))
  end
  local last = not comp:empty() and comp:back()
  if not last or last.start ~= start then
    log(S, "lock literal: no segment to confirm")
    return kAccepted
  end
  last._end = #ctx.input
  last.length = #ctx.input - start
  ctx:confirm_current_selection()
  log(S, "lock literal")
  return kAccepted
end }

ACTIONS.literal_space = { on_draft = true, run = function(S, env, ctx, draft)
  -- Design §5.5: a space into the draft, confirmed the same way. Natively
  -- Space with nothing left to select commits the whole draft untranslated
  -- (upstream F27). A space is an edit: a translation on screen goes first.
  void(ctx, draft)
  ctx:push_input(" ")
  ctx:confirm_current_selection()
  log(S, "literal space")
  return kAccepted
end }

-- The catch-all: any other key voids a translation on screen, then passes on
ACTIONS.invalidate_and_pass = { run = function(S, env, ctx, draft)
  void(ctx, draft)
  return kNoop
end }

local function processor(key, env)
  local S = shared.ensure()
  local ctx = env.engine.context

  -- On the first call, write any config warnings to the log
  if S.warnings and #S.warnings > 0 then
    for _, w in ipairs(S.warnings) do log(S, "config: " .. w) end
    S.warnings = {}
  end

  local draft = session.draft(ctx)

  -- modifier goes in raw: decide drops Lock and every bit it does not read
  -- (R15, Task 8). release is a method on the KeyEvent, not a field.
  local k = { keycode = key.keycode, modifier = key.modifier, release = key:release() }

  -- Feature 002 (design §5.5): every key goes past the Shift-tap watcher
  -- before any early return, so a key between a Shift press and its release
  -- is always seen and makes the Shift a modifier. The clock is librime-lua's
  -- (upstream F22); without one, observe drops the 500 ms limit.
  -- Feature 004 (design §5.6): the Right Option tap, watched the same way and
  -- as early, in its own property. It travels as a flag change (F21, F30),
  -- which applications do not take for themselves, so it works with no draft.
  local now = rime_api and rime_api.get_time_ms and rime_api.get_time_ms()
  local shift_tapped = watch(ctx, k, now, shift_tap.SHIFT)
  local option_tapped = watch(ctx, k, now, shift_tap.RIGHT_OPTION)

  -- Invalidation check number two (design §6.2): the draft changed while phase
  -- is still result/error -- a mouse click on a candidate, or any edit path we
  -- failed to anticipate. Every Enter passes here first, so a stale translation
  -- is never committed. The prompt goes with the phase.
  if session.stale(ctx) then
    void(ctx, draft)
    -- The edit that voided the phase came with no key event, so the prompt may
    -- still be on screen. An Esc here is aimed at it: take it as in the result
    -- phase; passed on, the native Esc would cancel the whole draft (design
    -- §5.2, S11 row 5b). With no draft left, Esc belongs to the app.
    if draft ~= "" and key.keycode == keys.ESC and not key:release() then
      return kAccepted
    end
  end

  -- A lone Shift tap switches Chinese and English (design §5.5). With a draft
  -- open, the current segment is locked first: confirmed, its conversion or
  -- its letters stay as they are, where switching first would re-read them as
  -- the other mode (the spike, decisions.md). It commits nothing and clears
  -- nothing. With the caret inside the input the composition stops at the
  -- caret (F15), so, as for Enter, the first tap only moves it to the end.
  if shift_tapped then
    if ctx.input ~= "" then
      if caret_inside(ctx) then
        ctx.caret_pos = #ctx.input
        return kAccepted
      end
      ctx:confirm_current_selection()
    end
    local ascii = not ctx:get_option("ascii_mode")
    ctx:set_option("ascii_mode", ascii)
    log(S, "shift tap: " .. (ascii and "english" or "chinese"))
    return kAccepted
  end

  -- Feature 004 (design §5.6): a lone Right Option tap switches the backend.
  -- Its press, a key like any other, has already voided a translation on
  -- screen (the catch-all); the switch does the rest.
  if option_tapped then return switch_backend(S, ctx, draft) end

  -- Empty is read from the input, which is what ctx:clear() removes. (librime
  -- composes the whole input when the caret is at the confirmed position, so
  -- the commit text is empty only when the input is; F15.)
  -- Feature 002 (design §5.5): is any of the input not yet selected?
  -- librime-lua reaches the confirmed position through toSegmentation()
  -- (upstream F27). In English mode the open part is letters already, so
  -- nothing counts as unselected and Enter translates at once (the user's
  -- decision, 002 Task 7 review).
  local unselected = ctx.input ~= "" and not ctx:get_option("ascii_mode")
    and ctx.composition:toSegmentation():get_confirmed_position() < #ctx.input
  local action = decide.decide(k, session.phase(ctx), ctx.input == "",
                               not draft:find("[\128-\255]"), unselected)

  local act = ACTIONS[action.type]
  if not act then return kNoop end
  if act.on_draft and caret_inside(ctx) then
    void(ctx, draft)
    ctx.caret_pos = #ctx.input
    return kAccepted
  end
  return act.run(S, env, ctx, draft)
end

return processor

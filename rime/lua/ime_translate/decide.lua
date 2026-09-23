-- Pure-function key decisions: references no rime global, does no IO, mutates
-- no state. The glue layer reads the context, executes the action and writes
-- state. That is what makes every branch unit-testable headless.
local state = require("ime_translate.state")
local M = {}

-- XK_KP_Enter counts as Enter: design §5.2 names the key, not a keysym, and
-- nothing in the native chain binds the keypad one outside ascii mode, so passed
-- through it reaches the application, whose newline replaces the draft.
M.RETURN, M.KP_ENTER, M.ESC = 0xFF0D, 0xFF8D, 0xFF1B
M.SPACE = 0x20
M.SHIFT, M.CONTROL, M.ALT, M.SUPER = 0x1, 0x4, 0x8, 0x4000000
-- The only modifier bits decide reads. Everything else is dropped first, Lock
-- (0x2) above all: Squirrel sets it on every key while Caps Lock is on, and an
-- Enter carrying it missed both Enter branches and reached the application
-- (spike R15).
M.MODIFIERS = M.SHIFT | M.CONTROL | M.ALT | M.SUPER

-- Returns { type = ... }:
--   noop                 leave it to later processors, i.e. native behaviour
--   translate            intercept Enter; the glue takes the draft to the backend
--   commit_translation   the processor commits the translation
--   commit_draft         the processor commits the Chinese draft -- skip, or a
--                        draft with no Chinese (design §5.5)
--   clear_display        discard the translation, back to idle, draft stays
--   invalidate_and_pass  void the translation first, then pass through
--   lock_literal         the processor locks what is not yet selected as the
--                        letters typed (design §5.5)
--   literal_space        the processor adds a literal space to the draft (§5.5)
function M.decide(key, phase, draft_empty, draft_ascii, unselected)
  if key.release then return { type = "noop" } end

  local code, mods = key.keycode, key.modifier & M.MODIFIERS
  local enter = code == M.RETURN or code == M.KP_ENTER

  if enter and mods == 0 then
    if draft_empty then return { type = "noop" } end
    if phase == state.RESULT then return { type = "commit_translation" } end
    -- Feature 005 (backend.md §8.1): Enter after an error asks again;
    -- Shift+Enter below is the way to the Chinese
    if phase == state.ERROR then return { type = "translate" } end
    -- design §5.5: unselected pinyin becomes the letters typed
    if unselected then return { type = "lock_literal" } end
    -- design §5.5: a draft with no Chinese has nothing to translate
    if draft_ascii then return { type = "commit_draft" } end
    return { type = "translate" }
  end

  -- Escape hatch: do not translate this one, just commit the Chinese
  if enter and mods == M.SHIFT then
    if draft_empty then return { type = "noop" } end
    return { type = "commit_draft" }
  end

  -- design §5.5: Space with a draft open and nothing unselected is a literal
  -- space. Natively it would commit the whole draft untranslated (F27), and so
  -- would Shift+Space, which fluid_editor's key map falls back to Space
  -- (002 Task 7 review, yellow 2).
  if code == M.SPACE and (mods == 0 or mods == M.SHIFT)
     and not draft_empty and not unselected then
    return { type = "literal_space" }
  end

  -- Esc with any modifier: librime's Editor falls back from Shift+Escape to
  -- Escape, so passing a modified Esc on would cancel the draft all the same.
  if code == M.ESC and phase ~= state.IDLE then
    return { type = "clear_display" }
  end

  -- Catch-all: with a translation on screen, any other key invalidates it
  -- before passing through. Rather than enumerating "which keys change the
  -- draft", this covers typing, backspace, cursor movement and candidate
  -- navigation in one rule.
  if phase ~= state.IDLE then return { type = "invalidate_and_pass" } end
  return { type = "noop" }
end

return M

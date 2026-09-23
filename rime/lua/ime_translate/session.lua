-- Session state, all stored in librime Context properties, isolated per
-- session. Do not put any of this in module upvalues: librime-lua gives every
-- component one shared Lua state, so module-level state leaks translations
-- between applications and input boxes.
local state = require("ime_translate.state")
local M = {}

local K_PHASE = "ime_translate.phase"
local K_TEXT  = "ime_translate.text"
local K_CODE  = "ime_translate.code"
local K_DRAFT = "ime_translate.draft"
-- Feature 003 (design §5.6): "1" when the result or error on screen came from
-- a non-loopback base_url
local K_CLOUD = "ime_translate.cloud"
-- Feature 005 (design §6.4): "1" when the cloud slot failed and the result on
-- screen is the local slot's
local K_FALLBACK = "ime_translate.fallback"

-- Under fluid_editor the composition does not auto-commit, so
-- get_commit_text() returns the whole Chinese draft, confirmed segments
-- included -- with the caret at the end. With the caret inside the input it
-- stops at the caret; the processor moves the caret to the end before acting
-- on the draft (design §5.2, Task 9 review).
function M.draft(ctx) return ctx:get_commit_text() or "" end

function M.phase(ctx)
  local p = ctx:get_property(K_PHASE)
  if p == nil or p == "" then return state.IDLE end
  return p
end

function M.text(ctx)     return ctx:get_property(K_TEXT)  or "" end
function M.code(ctx)     return ctx:get_property(K_CODE)  or "" end
function M.snapshot(ctx) return ctx:get_property(K_DRAFT) or "" end

-- Features 002 and 004 (design §5.5, §5.6): a tap key's `down` (shift_tap), the
-- key pressed alone and not yet released -- its keycode and the time it went
-- down. One property per tap descriptor, "ime_translate." .. tap.prop:
-- shift_down for Shift, option_down for Right Option. Kept apart from clear():
-- a press in the result phase voids the translation, and its tap must still
-- count. Stored as "keycode@ms", "keycode@" with no clock.
function M.tap_down(ctx, tap)
  local code, at = (ctx:get_property("ime_translate." .. tap.prop) or ""):match("^(%d+)@(%d*)$")
  if not code then return nil end
  return { code = tonumber(code), at = tonumber(at) }
end
function M.set_tap_down(ctx, tap, down)
  ctx:set_property("ime_translate." .. tap.prop, down and (down.code .. "@" .. (down.at or "")) or "")
end

function M.set_result(ctx, draft, text, cloud, fallback)
  ctx:set_property(K_DRAFT, draft)
  ctx:set_property(K_TEXT, text)
  ctx:set_property(K_CODE, "")
  ctx:set_property(K_CLOUD, cloud and "1" or "")
  ctx:set_property(K_FALLBACK, fallback and "1" or "")
  ctx:set_property(K_PHASE, state.RESULT)
end

function M.set_error(ctx, draft, code, cloud)
  ctx:set_property(K_DRAFT, draft)
  ctx:set_property(K_TEXT, "")
  ctx:set_property(K_CODE, code)
  ctx:set_property(K_CLOUD, cloud and "1" or "")
  ctx:set_property(K_FALLBACK, "")
  ctx:set_property(K_PHASE, state.ERROR)
end

function M.clear(ctx)
  ctx:set_property(K_PHASE, state.IDLE)
  ctx:set_property(K_TEXT, "")
  ctx:set_property(K_CODE, "")
  ctx:set_property(K_DRAFT, "")
  ctx:set_property(K_CLOUD, "")
  ctx:set_property(K_FALLBACK, "")
end

-- Has the translation expired? The draft text is its own version identifier;
-- there is no separate counter. That holds only because the display stays out
-- of get_commit_text() (design §6.1, decision D1).
function M.stale(ctx)
  if M.phase(ctx) == state.IDLE then return false end
  return M.draft(ctx) ~= M.snapshot(ctx)
end

-- The display (design §6.4): what the processor writes into the last
-- segment's prompt. "  -> " is the form spike S11 measured in the preedit.
-- Feature 003: a cloud answer shows "☁" instead, the explicit marker design
-- §7.2 asks for. Feature 005: a local answer after a failed cloud request
-- is marked "☁✗" before it.
function M.prompt(ctx)
  local p = M.phase(ctx)
  local cloud = ctx:get_property(K_CLOUD) == "1"
  if p == state.RESULT then
    local fallback = ctx:get_property(K_FALLBACK) == "1"
    return "  " .. (fallback and "☁✗ " or "") .. (cloud and "☁ " or "-> ") .. M.text(ctx)
  end
  if p == state.ERROR then
    return "  " .. (cloud and "☁ " or "") .. state.error_message(M.code(ctx))
  end
  return ""
end

return M

package.path = package.path .. ";rime/lua/?.lua;tests/?.lua"
-- The processor, features 003-005 (design §5.6, backend.md §8.1): the backend
-- switch, the Right Option tap, the cloud fallback and the cache.
-- The fake engine, the stubbed backend and the key helpers are in
-- processor_support.lua.
local T = require("processor_support")
local shared = require("ime_translate_shared")
local config = require("ime_translate.config")
local backend = require("ime_translate.backend")
local processor = require("ime_translate_processor")
local cache = require("ime_translate.cache")
local eq, fake, key, press, trace, tap, otap = T.eq, T.fake, T.key, T.press, T.trace, T.tap, T.otap
local kAccepted, kNoop = T.kAccepted, T.kNoop
local RET, ESC, B = 0xFF0D, 0xFF1B, 0x42
local SHIFT, CTRL, ALT, REL = 0x1, 0x4, 0x8, 1 << 30
local ALT_R = 0xFFEA
local env, ctx, seg
---------- feature 003 (design §5.6): the switch and the active slot ----------
-- A switch writes the active file: never the real one under ~/Library
local ACTIVE = os.tmpname()
shared.active_path = ACTIVE
local function slurp(path)
  local f = io.open(path, "r"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local local_settings = shared.settings
local cloud_settings = config.load(function()
  return "allow_remote: true\ncloud_backend: openai\ncloud_base_url: https://api.example.com/v1\n"
end).cloud
assert(cloud_settings, "the cloud fixture loads")

-- no cloud slot: the switch stays local and says so
env, ctx, seg = fake("今天有点累")
eq(otap(env), kAccepted, "a Right Option tap is taken")
eq(trace(ctx), "ime_translate_notice_no_cloud=true,ime_translate_notice_no_cloud=false",
   "no cloud slot: the no-cloud notice, on then off")
eq(shared.active, "local", "no cloud slot: still local")
eq(#env.committed, 0, "the switch commits nothing")
eq(ctx._text, "今天有点累", "the draft is intact")

-- with a cloud slot: translate locally, switch, translate the same draft again
shared.settings.cloud, shared.cloud_key = cloud_settings, "cloud-sentinel"
env, ctx, seg = fake("今天有点累")
T.answer, T.calls = { true, "I'm a little tired today" }, {}
press(env, RET)
eq(T.args.settings, local_settings, "local: the local settings")
eq(T.args.key, "k-sentinel", "local: the local key")
eq(seg.prompt, "  -> I'm a little tired today", "a loopback translation is unmarked")
eq(otap(env), kAccepted, "the switch is taken in result")
eq(seg.prompt, "", "the translation on screen is voided")
eq(ctx:get_property("ime_translate.phase"), "idle", "back to idle")
eq(shared.active, "cloud", "switched to cloud")
eq(trace(ctx), "ime_translate_notice_cloud=true,ime_translate_notice_cloud=false",
   "the cloud notice, on then off")
eq(slurp(ACTIVE), "cloud\n", "the switch is remembered")
eq(#env.committed, 0, "nothing committed by the switch")
eq(ctx._text, "今天有点累", "the draft is intact after the switch")
T.answer, T.calls = { true, "A bit tired today" }, {}
eq(press(env, RET), kAccepted, "enter translates again")
eq(T.calls[1], "今天有点累", "the same draft")
eq(T.args.settings, cloud_settings, "with the cloud settings")
eq(T.args.key, "cloud-sentinel", "and the cloud key")
eq(seg.prompt, "  ☁ A bit tired today", "a cloud translation is marked")
eq(press(env, RET), kAccepted, "enter commits it")
eq(env.committed[1], "A bit tired today", "the cloud translation is committed")

-- a cloud error with the local slot failing too: the cloud's error, marked;
-- Shift+Enter commits the Chinese (feature 005)
env, ctx, seg = fake("今天")
T.answer, T.calls = { false, "timeout" }, {}
press(env, RET)
eq(#T.calls, 2, "the cloud, then the local fallback")
eq(seg.prompt, "  ☁ ✗ 翻译超时", "a cloud error is marked")
press(env, RET, SHIFT)
eq(env.committed[1], "今天", "shift-enter commits the draft")

-- feature 005: the cloud fails, the local slot answers. The stub answers by
-- the settings it is given.
env, ctx, seg = fake("今天有点累")
T.calls = {}
local by_slot = backend.translate
backend.translate = function(settings, text, runner, key)
  by_slot(settings, text, runner, key)
  if settings.base_url == cloud_settings.base_url then return false, "timeout" end
  return true, "Tired"
end
eq(press(env, RET), kAccepted, "enter is taken")
eq(#T.calls, 2, "the cloud, then the local slot")
eq(T.args.settings.base_url, local_settings.base_url, "the second request is the local slot's")
eq(T.args.settings.timeout_ms, 500, "within the 500 ms left")
eq(T.args.key, "k-sentinel", "with the local key")
eq(seg.prompt, "  ☁✗ -> Tired", "the fallback is marked")
eq(#env.committed, 0, "nothing committed yet")
eq(press(env, RET), kAccepted, "enter commits it")
eq(env.committed[1], "Tired", "the local translation is committed")
-- Esc, then Enter on the same draft: the cloud is asked again, since only its
-- failure was seen, and the local answer comes from the cache
env, ctx, seg = fake("今天有点累")
T.calls = {}
press(env, RET)
press(env, ESC)
press(env, RET)
eq(#T.calls, 3, "cloud, local, then cloud again; the local answer is cached")
eq(seg.prompt, "  ☁✗ -> Tired", "the fallback shows again")
backend.translate = by_slot
-- a cloud success is cached: Esc then Enter makes no request
env, ctx, seg = fake("今天")
T.answer, T.calls = { true, "Today" }, {}
press(env, RET); press(env, ESC); press(env, RET)
eq(#T.calls, 1, "one request for two enters")
eq(seg.prompt, "  ☁ Today", "the cached cloud translation, marked")

-- the switch with no draft: taken, and back to local
env, ctx, seg = fake("")
eq(otap(env), kAccepted, "the switch with no draft is taken")
eq(shared.active, "local", "back to local")
eq(trace(ctx), "ime_translate_notice_local=true,ime_translate_notice_local=false",
   "the local notice")
eq(slurp(ACTIVE), "local\n", "local is remembered")
eq(#env.committed, 0, "nothing committed with no draft")

-- feature 004: none of these switches the backend. The no-clock block above
-- left rime_api unset; the long hold below needs the fake clock back.
T.use_clock()
env, ctx, seg = fake("今天")
eq(press(env, B, CTRL | SHIFT), kNoop, "ctrl+shift+B is native again: it passes")
eq(shared.active, "local", "and switches nothing")
processor(key(0xFFE9, ALT), env)
eq(processor(key(0xFFE9, REL, true), env), kNoop, "a Left Option release passes")
eq(shared.active, "local", "a Left Option tap switches nothing")
processor(key(ALT_R, ALT), env)
T.clock = T.clock + 600
eq(processor(key(ALT_R, REL, true), env), kNoop, "a Right Option held past 500 ms is not a tap")
eq(shared.active, "local", "and switches nothing")
-- a new input box: the long hold above must leave no state behind to mask
-- this case (004 Task 1 review, yellow 2)
env, ctx, seg = fake("今天")
processor(key(ALT_R, ALT), env)
processor(key(string.byte("e"), ALT), env)
eq(processor(key(ALT_R, REL, true), env), kNoop, "Option+letter is a chord")
eq(shared.active, "local", "and switches nothing")
eq(trace(ctx), "", "no notice for any of them")

-- Task 4 review, round 1, green: from an error the switch voids the error,
-- so Enter translates with the other slot instead of committing the Chinese
env, ctx, seg = fake("今天")
T.answer = { false, "timeout" }
press(env, RET)
eq(seg.prompt, "  ✗ 翻译超时", "a local error is unmarked")
eq(otap(env), kAccepted, "the switch is taken in error")
eq(seg.prompt, "", "the error on screen is voided")
eq(ctx:get_property("ime_translate.phase"), "idle", "back to idle from error")
eq(shared.active, "cloud", "switched to cloud from error")
T.answer, T.calls = { true, "Today" }, {}
press(env, RET)
eq(T.calls[1], "今天", "enter translates the same draft")
eq(T.args.settings, cloud_settings, "with the cloud slot")
eq(seg.prompt, "  ☁ Today", "and shows it, marked")
eq(#env.committed, 0, "nothing committed along the way")
-- with the caret inside the input the switch still happens at once; it does
-- not act on the draft, so it does not first move the caret (design §5.2)
env, ctx, seg = fake("今天有点累", "jintianyoudianlei")
ctx.caret_pos = 3
eq(otap(env), kAccepted, "the switch with the caret inside is taken")
eq(shared.active, "local", "it switched at once")
eq(ctx.caret_pos, 3, "the caret did not move")

-- feature 004: a Shift tap and a Right Option tap do not disturb each other
env, ctx, seg = fake("今天", "jintian")
local _, shift_released = tap(env)
eq(shift_released, kAccepted, "a Shift tap is still taken")
eq(ctx.opts.ascii_mode, true, "and switches to English")
eq(shared.active, "local", "a Shift tap switches no backend")
eq(otap(env), kAccepted, "then a Right Option tap is taken")
eq(shared.active, "cloud", "and switches the backend")
eq(ctx.opts.ascii_mode, true, "leaving the mode the Shift tap set")

-- the URL decides the marker: a local slot pointed at a cloud is marked
shared.settings = config.load(function()
  return "allow_remote: true\nbackend: openai\nbase_url: https://api.example.com/v1\n"
end)
env, ctx, seg = fake("今天")
T.answer = { true, "Today" }
press(env, RET)
eq(seg.prompt, "  ☁ Today", "a remote URL in the local slot is marked")

shared.settings, local_settings.cloud, shared.cloud_key = local_settings, nil, nil
shared.active = "local"
os.remove(ACTIVE)

T.done("test_processor_switch")

-- Feature 005 (backend.md §8.1, §8.3): which slot answers an Enter. First the
-- cache, then the active slot, then -- for a failed cloud only -- the local
-- slot within the 500 ms the cloud's cap leaves (§8.2). A local failure is
-- never sent to the cloud: the user has not chosen the cloud for it.
--
-- S is ime_translate_shared: settings, api_key, cache and current(). The
-- runner is injected, as for backend.translate, so the tests never shell out.
local backend = require("ime_translate.backend")
local config = require("ime_translate.config")
local M = {}

M.FALLBACK_MS = 500

-- Ask one slot, through the cache. Only a success is cached: Enter after an
-- error must ask again.
local function ask(S, slot, settings, key, draft, runner)
  local hit = S.cache:get(slot, draft)
  if hit then return true, hit end
  local ok, out = backend.translate(settings, draft, runner, key)
  if ok then S.cache:put(slot, draft, out) end
  return ok, out
end

-- -> { ok, text, code, cloud, fallback }. cloud: the settings that answered
-- have a non-loopback base_url (the §7.2 marker).
function M.translate(S, draft, runner)
  local settings, key, slot = S.current()
  local cloud = not config.is_loopback(settings.base_url)
  local ok, out = ask(S, slot, settings, key, draft, runner)
  if ok then return { ok = true, text = out, cloud = cloud, fallback = false } end
  local failed = { ok = false, code = out, cloud = cloud, fallback = false }
  -- max_chars is shared, so the local slot would refuse too_long as well
  if slot ~= "cloud" or out == "too_long" then return failed end

  -- A copy: the local slot's own timeout stays as configured
  local fb = {}
  for k, v in pairs(S.settings) do fb[k] = v end
  fb.timeout_ms = M.FALLBACK_MS
  local ok2, out2 = ask(S, "local", fb, S.api_key, draft, runner)
  if not ok2 then return failed end
  return { ok = true, text = out2, cloud = not config.is_loopback(fb.base_url), fallback = true }
end

return M

package.path = package.path .. ";rime/lua/?.lua"
-- Feature 005 (backend.md §8.1, §8.3): which slot answers an Enter -- the
-- cache, the active slot, then the local slot for a failed cloud. The runner
-- is a fake, so nothing here runs curl.
local route = require("ime_translate.route")
local cache = require("ime_translate.cache")
local config = require("ime_translate.config")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

local CFG = "api_key_account: local-acct\nallow_remote: true\ncloud_backend: openai\n" ..
            "cloud_base_url: https://api.example.com/v1\ncloud_model: m\ncloud_api_key_account: cloud-acct\n"
-- A stand-in for ime_translate_shared: the same fields route reads
local function fake_shared(active)
  local S = { settings = (config.load(function() return CFG end)), api_key = "LOCAL-KEY",
              cloud_key = "CLOUD-KEY", active = active, cache = cache.new(32) }
  function S.current()
    if S.active == "cloud" then return S.settings.cloud, S.cloud_key end
    return S.settings, S.api_key
  end
  return S
end
-- A runner that answers by URL and counts: local is 127.0.0.1, cloud is not
local calls
local function runner(answers)
  calls = {}
  return function(cmd)
    local where = cmd:find("127.0.0.1", 1, true) and "local" or "cloud"
    calls[#calls + 1] = { where = where, cmd = cmd }
    local a = answers[where]
    return a[1], a[2], a[3]
  end
end
local LOCAL_OK = { '{"translatedText":"Hello"}', 200, 0 }
local CLOUD_OK = { '{"choices":[{"message":{"content":"Hi there"}}]}', 200, 0 }
local TIMEOUT = { "", 0, 28 }
local REFUSED = { "", 0, 7 }

-- local success, then a cache hit with no request
local S = fake_shared("local")
local r = route.translate(S, "你好", runner({ ["local"] = LOCAL_OK }))
eq(r.ok, true, "local success"); eq(r.text, "Hello", "local text")
eq(r.cloud, false, "local is not cloud"); eq(r.fallback, false, "no fallback")
eq(#calls, 1, "one request")
r = route.translate(S, "你好", runner({ ["local"] = REFUSED }))
eq(r.ok, true, "the second Enter is a cache hit"); eq(r.text, "Hello", "the cached text")
eq(#calls, 0, "no request on a hit")

-- local failure: its error, no cloud request, nothing cached
S = fake_shared("local")
r = route.translate(S, "你好", runner({ ["local"] = REFUSED, cloud = CLOUD_OK }))
eq(r.ok, false, "local failure"); eq(r.code, "conn_refused", "its code")
eq(#calls, 1, "a local failure is never sent to the cloud")
eq(calls[1].where, "local", "the one request was local")
r = route.translate(S, "你好", runner({ ["local"] = LOCAL_OK }))
eq(#calls, 1, "an error was not cached: the next Enter asks again")
eq(r.text, "Hello", "and gets the answer")

-- cloud success
S = fake_shared("cloud")
r = route.translate(S, "你好", runner({ cloud = CLOUD_OK, ["local"] = LOCAL_OK }))
eq(r.ok, true, "cloud success"); eq(r.text, "Hi there", "cloud text")
eq(r.cloud, true, "marked cloud"); eq(r.fallback, false, "not a fallback")
eq(#calls, 1, "one request")
assert(calls[1].cmd:find("CLOUD-KEY", 1, true), "the cloud request carries the cloud key")

-- cloud timeout, then local: a fallback with a 500 ms timeout
S = fake_shared("cloud")
r = route.translate(S, "你好", runner({ cloud = TIMEOUT, ["local"] = LOCAL_OK }))
eq(r.ok, true, "the fallback succeeds"); eq(r.text, "Hello", "the local text")
eq(r.fallback, true, "marked fallback"); eq(r.cloud, false, "the answer is loopback")
eq(#calls, 2, "cloud, then local")
eq(calls[1].where, "cloud", "cloud first"); eq(calls[2].where, "local", "local second")
assert(calls[1].cmd:find("%-%-max%-time 1%.500"), "the cloud keeps its own timeout")
assert(calls[2].cmd:find("%-%-max%-time 0%.500"), "the fallback's timeout is 500 ms")
-- 005 Task 3 review, yellow: the fallback carries the local key, never the
-- cloud's. An openai local slot sends its key, so the cloud key would leak to it.
eq(route.FALLBACK_MS, 500, "FALLBACK_MS is 500")
eq(S.settings.timeout_ms, 1500, "the local settings are not changed by the fallback")
-- the fallback was cached under local, not cloud: the next cloud Enter asks the cloud
r = route.translate(S, "你好", runner({ cloud = CLOUD_OK, ["local"] = REFUSED }))
eq(r.text, "Hi there", "the cloud is asked again"); eq(r.fallback, false, "and answers")
eq(#calls, 1, "one request")
S.active = "local"
r = route.translate(S, "你好", runner({ ["local"] = REFUSED }))
eq(r.text, "Hello", "the fallback's answer is cached under local"); eq(#calls, 0, "no request")

local CFG_OA = "backend: openai\nbase_url: http://127.0.0.1:11434/v1\nmodel: m\n" .. CFG
S = fake_shared("cloud")
S.settings = config.load(function() return CFG_OA end)
r = route.translate(S, "你好", runner({ cloud = TIMEOUT,
  ["local"] = { '{"choices":[{"message":{"content":"Hello"}}]}', 200, 0 } }))
eq(r.fallback, true, "an openai local slot falls back too")
assert(calls[2].cmd:find("LOCAL-KEY", 1, true), "the fallback request carries the local key")
assert(not calls[2].cmd:find("CLOUD-KEY", 1, true), "and never the cloud key")

-- a cloud failure with a cached local answer: no local request
S = fake_shared("local")
route.translate(S, "你好", runner({ ["local"] = LOCAL_OK }))
S.active = "cloud"
r = route.translate(S, "你好", runner({ cloud = TIMEOUT, ["local"] = REFUSED }))
eq(r.fallback, true, "the fallback comes from the cache"); eq(r.text, "Hello", "cached text")
eq(#calls, 1, "only the cloud request")

-- cloud failure, local failure: the cloud's error
S = fake_shared("cloud")
r = route.translate(S, "你好", runner({ cloud = { "", 401, 0 }, ["local"] = REFUSED }))
eq(r.ok, false, "both fail"); eq(r.code, "auth_error", "the cloud's code shows")
eq(r.cloud, true, "marked cloud"); eq(r.fallback, false, "not a fallback")
eq(#calls, 2, "cloud, then local")

-- too_long never falls back: max_chars is shared
S = fake_shared("cloud")
r = route.translate(S, string.rep("长", 2001), runner({ cloud = CLOUD_OK, ["local"] = LOCAL_OK }))
eq(r.code, "too_long", "too long"); eq(#calls, 0, "no request at all")

-- no cloud slot: current() is local, and a local failure stays local
S = fake_shared("cloud")
S.settings.cloud = nil
S.current = function() return S.settings, S.api_key end
r = route.translate(S, "你好", runner({ ["local"] = REFUSED }))
eq(r.code, "conn_refused", "local error"); eq(#calls, 1, "one request")

print(("test_route: %d assertions OK"):format(n))

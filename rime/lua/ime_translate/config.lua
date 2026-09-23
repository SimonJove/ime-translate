-- Flat key: value config (one per line, # comments). Only keys documented
-- in this file are accepted.
local M = {}

local DEFAULT_PROMPT = "你是翻译器。把用户的中文翻译成自然、简洁、适合即时聊天语境的英文。" ..
  "只输出译文——不要解释、不要引号、不要前缀。保留语气、emoji、数字、URL、代码标识符和换行。" ..
  "如果文本基本没有中文，原样返回。"

local DEFAULTS = {
  -- decision D4: translate is the default; apfel cannot run on the dev machine
  backend = "libretranslate",   -- openai | libretranslate | anthropic
  base_url = "http://127.0.0.1:8989",
  model = "",              -- libretranslate takes no model
  prompt = DEFAULT_PROMPT,
  -- design §8.2: under a synchronous blocking model this value IS the IME's
  -- worst-case freeze after Enter. Local default 1500ms; past one second the
  -- experience has already collapsed, and waiting until three only prolongs it.
  timeout_ms = 1500,
  max_chars = 2000,        -- characters, not bytes
  -- Available to adapters, but **each adapter decides whether to send it**.
  -- Claude Opus 5 / Sonnet 5 removed the parameter; sending it returns 400.
  temperature = 0.2,
  max_tokens = 1024,       -- required by the anthropic adapter
  allow_remote = false,    -- when false, any non-loopback base_url is refused
  api_key_account = "",    -- the Keychain account name; never the secret itself
  debug_log = false,
}

local BOOLS = { debug_log = true, allow_remote = true }
local NUMS = { timeout_ms = true, max_chars = true, temperature = true, max_tokens = true }
local BACKENDS = { openai = true, libretranslate = true, anthropic = true }
-- Feature 003 (backend.md §9): the keys each backend slot owns. The cloud slot
-- is the same set under the cloud_ prefix; every other key is shared.
local SLOT_KEYS = { backend = true, base_url = true, model = true, prompt = true,
                    timeout_ms = true, temperature = true, max_tokens = true,
                    api_key_account = true }
local CLOUD = "cloud_"

-- One YAML scalar: a quoted value keeps any # inside its quotes; otherwise a #
-- that starts the value, or follows whitespace, begins a comment.
local function scalar(v)
  local q = v:sub(1, 1)
  if q == '"' or q == "'" then
    local inner, rest = v:match("^" .. q .. "(.-)" .. q .. "(.*)$")
    if inner and (rest:match("^[ \t]*$") or rest:match("^[ \t]+#")) then return inner end
  end
  if q == "#" then return "" end
  return (v:gsub("[ \t]+#.*$", ""))
end

-- The host must BE loopback, not merely start like it. A prefix match accepted
-- "127.0.0.1.evil.example", "localhost.evil.example" and "127.0.0.1@evil.example"
-- (userinfo: the real host follows the @) -- each sends every typed sentence off
-- the machine without allow_remote, and over plain http even with it. And curl
-- expands {a,b} and [a-b] globs before it parses a URL, so
-- "localhost:8989{/,@evil.example/}" is two requests, the second to evil.example.
-- So the authority must be exactly a host, or a host and a numeric port; userinfo
-- and glob syntax both fail that. Anything unrecognised counts as remote.
local function is_loopback(url)
  local authority = url:match("^https?://([^/?#]*)")
  if not authority then return false end
  local host, port = authority:match("^([^:]*)(.*)$")
  if port ~= "" and not port:match("^:%d+$") then return false end
  host = host:lower()
  return host == "127.0.0.1" or host == "localhost"
end
-- Exported so the backend (proxy bypass) and the §7.2 cloud marker reuse this
-- verdict instead of deriving a second one.
M.is_loopback = is_loopback

-- One slot's adapter and trust checks: the reason it fails, or nil. A reason
-- names keys, never values (design §7.3).
local function refusal(s)
  -- An unknown adapter name would make every Enter fail with no reason logged.
  if not BACKENDS[s.backend] then return "unknown backend" end
  -- Tiered trust: loopback only by default; remote needs allow_remote, and
  -- remote must be https.
  if not is_loopback(s.base_url) then
    if not s.allow_remote then return "non-loopback base_url needs allow_remote: true" end
    if not s.base_url:find("^https://") then return "remote base_url must use https" end
  end
  return nil
end

-- One slot's timeout_ms (design §8.2): it is the worst-case freeze after
-- Enter. D10, the user's decision: past about 2500 ms some applications lose
-- the draft (spike S13; TextEdit did at 5000 in 003's smoke), so a larger value
-- is capped at 2500. One below 500 falls back to the default.
-- Feature 005 (§8.2): the cloud's ceiling is 2000, so the local fallback that
-- follows a failed cloud request has 500 ms and the freeze stays 2500.
local TIMEOUT_MIN, TIMEOUT_MAX, CLOUD_TIMEOUT_MAX = 500, 2500, 2000
local function bound_timeout(s, key, warnings, max, why)
  if s.timeout_ms > max then
    warnings[#warnings + 1] = ("%s above %d %s; capped at %d"):format(key, max, why, max)
    s.timeout_ms = max
  elseif s.timeout_ms < TIMEOUT_MIN then
    warnings[#warnings + 1] = key .. " below 500; fell back to default"
    s.timeout_ms = DEFAULTS.timeout_ms
  end
end

function M.load(read_fn)
  local out = {}
  for k, v in pairs(DEFAULTS) do out[k] = v end
  local warnings = {}
  local cloud = {}   -- the cloud_ keys given, under their bare names
  local raw = read_fn()
  if raw then
    -- Every line is counted, blank ones too, so a warning can name its line.
    -- Warnings carry line numbers and key names, never values (design §7.3).
    local lineno = 0
    for line in (raw .. "\n"):gmatch("(.-)\n") do
      lineno = lineno + 1
      line = line:gsub("\r$", "")
      if lineno == 1 then line = line:gsub("^\239\187\191", "") end   -- UTF-8 BOM
      -- [ \t], not %s: %s is C's isspace(), which under a UTF-8 ctype on macOS
      -- also matches 0xA0 -- the last byte of some CJK characters in a prompt.
      if not (line:match("^[ \t]*$") or line:match("^[ \t]*#")) then
        local k, v = line:match("^[ \t]*([%w_]+)[ \t]*:[ \t]*(.-)[ \t]*$")
        local take = false
        if not k then
          -- a full-width colon, a dashed key: dropping these silently hid them
          warnings[#warnings + 1] = ("line %d not understood"):format(lineno)
        elseif v:match("^[|>]") then
          -- a YAML block scalar: its body is on the following lines, which this
          -- flat parser cannot read, so refuse it and keep the default. A quoted
          -- value starting with | or > is not a block scalar and is kept.
          warnings[#warnings + 1] = "block scalars are not supported: " .. k
        else
          v = scalar(v)
          take = v ~= ""
        end
        if take then
          -- Feature 003: a cloud_ slot key goes to the cloud slot under its
          -- bare name. The warnings keep the key as written.
          local dest, key = out, k
          if k:sub(1, #CLOUD) == CLOUD and SLOT_KEYS[k:sub(#CLOUD + 1)] then
            dest, key = cloud, k:sub(#CLOUD + 1)
          end
          if DEFAULTS[key] == nil then
            warnings[#warnings + 1] = "unknown config key: " .. k
          elseif BOOLS[key] then
            -- true or false only. Anything else resets to the default (both
            -- bools default to false, so this fails closed) and warns -- it must
            -- not leave an earlier line's "true" standing.
            local lv = v:lower()
            if lv == "true" then dest[key] = true
            elseif lv == "false" then dest[key] = false
            else
              dest[key] = DEFAULTS[key]
              warnings[#warnings + 1] = "not true or false: " .. k
            end
          elseif NUMS[key] then
            local num = tonumber(v)
            if num then dest[key] = num else warnings[#warnings + 1] = "not a number: " .. k end
          else
            dest[key] = v
          end
        end
      end
    end
  end
  local why = refusal(out)
  if why then
    warnings[#warnings + 1] = why .. "; fell back to the default backend"
    -- the triple falls back together: a libretranslate URL under the openai
    -- adapter would fail with a misleading error
    out.backend, out.base_url, out.model = DEFAULTS.backend, DEFAULTS.base_url, DEFAULTS.model
  end
  bound_timeout(out, "timeout_ms", warnings, TIMEOUT_MAX, "can lose the draft")
  if out.max_chars < 1 or out.max_chars > 5000 then
    warnings[#warnings + 1] = "max_chars out of range [1,5000]; fell back to default"
    out.max_chars = DEFAULTS.max_chars
  end
  -- Feature 003 (backend.md §9): the cloud slot exists only when cloud_backend
  -- is set. It starts from the defaults, not from the local slot, and takes
  -- the shared keys from the local one, already checked. One that fails a
  -- check is dropped, never replaced by the default backend: that would make
  -- "cloud" silently mean translate.
  if cloud.backend then
    local s = {}
    for k, v in pairs(DEFAULTS) do
      if SLOT_KEYS[k] then s[k] = v else s[k] = out[k] end
    end
    for k, v in pairs(cloud) do s[k] = v end
    -- D9, the user's decision: a cloud slot names its server. The loopback
    -- default would make every cloud Enter fail against the local service.
    local cwhy = not cloud.base_url and "cloud_base_url not set" or refusal(s)
    if cwhy then
      warnings[#warnings + 1] = "cloud slot dropped: " .. cwhy
    else
      bound_timeout(s, "cloud_timeout_ms", warnings, CLOUD_TIMEOUT_MAX,
                    "leaves the local fallback under 500 ms")
      out.cloud = s
    end
  elseif next(cloud) then
    warnings[#warnings + 1] = "cloud_ keys without cloud_backend; no cloud slot"
  end
  return out, warnings
end

return M

package.path = package.path .. ";rime/lua/?.lua"
local config = require("ime_translate.config")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end
local function load(text) return config.load(function() return text end) end

-- defaults
local d = load(nil)
eq(d.backend, "libretranslate", "default backend is translate (decision D4)")
eq(d.base_url, "http://127.0.0.1:8989", "default base_url")
eq(d.model, "", "default model: libretranslate takes none")
eq(d.timeout_ms, 1500, "default timeout is 1500, not 3000")
eq(d.max_chars, 2000, "default max_chars")
eq(d.temperature, 0.2, "default temperature")
eq(d.max_tokens, 1024, "default max_tokens")
eq(d.allow_remote, false, "default allow_remote off")
eq(d.api_key_account, "", "default api_key_account empty")
eq(d.debug_log, false, "default debug_log")
eq(d.toggle_keycode, nil, "toggle keys are not this project's config")
eq(d.toggle_modifier, nil, "toggle keys are not this project's config (modifier)")
assert(d.prompt:find("只输出译文"), "default prompt present")

-- parsing
local p = load("timeout_ms: 900\nmax_chars: 50\ndebug_log: true\nmodel: foo\n")
eq(p.timeout_ms, 900, "parse int")
eq(p.max_chars, 50, "parse int 2")
eq(p.debug_log, true, "parse bool")
eq(p.model, "foo", "parse string")

-- comments and blank lines are ignored
local c = load("# comment\n\n   # indented comment\nmodel: bar\n")
eq(c.model, "bar", "comments ignored")

-- an unknown key warns rather than being silently dropped
local _, w1 = load("nonsense_key: 1\n")
eq(#w1, 1, "unknown key warns")
assert(w1[1]:find("nonsense_key"), "warning names the key")

-- non-numeric warns and falls back
local b, w2 = load("timeout_ms: abc\n")
eq(b.timeout_ms, 1500, "non-numeric falls back")
eq(#w2, 1, "non-numeric warns")

-- out of range falls back
local o1 = load("timeout_ms: 99\n");    eq(o1.timeout_ms, 1500, "timeout below floor")
-- D10, the user's decision (2026-09-22): past about 2500 ms some applications
-- lose the draft (spike S13; TextEdit did at 5000 in 003's smoke), so a larger
-- value is capped at 2500 rather than reset to the default
local o2, wo2 = load("timeout_ms: 99999\n"); eq(o2.timeout_ms, 2500, "timeout above ceiling is capped at 2500")
eq(#wo2, 1, "the cap warns")
eq(load("timeout_ms: 2500\n").timeout_ms, 2500, "2500 itself is kept")
eq(load("timeout_ms: 2501\n").timeout_ms, 2500, "2501 is capped")
eq(load("timeout_ms: 5000\n").timeout_ms, 2500, "5000 is capped")
eq(load("timeout_ms: 500\n").timeout_ms, 500, "500 itself is kept")
eq(load("timeout_ms: 1e999\n").timeout_ms, 2500, "an infinite value is capped")
local o3 = load("max_chars: 0\n");      eq(o3.max_chars, 2000, "max_chars below floor")
local o4 = load("max_chars: 99999\n");  eq(o4.max_chars, 2000, "max_chars above ceiling")

-- tiered trust: non-loopback without allow_remote is refused and falls back
local r1, wr1 = load("backend: anthropic\nbase_url: https://api.anthropic.com/v1\n")
eq(r1.base_url, "http://127.0.0.1:8989", "remote rejected without allow_remote")
eq(r1.backend, "libretranslate", "the whole backend falls back, not only base_url")
eq(#wr1, 1, "rejection warns")
-- allow_remote plus https is accepted
local r2 = load("allow_remote: true\nbase_url: https://api.anthropic.com/v1\n")
eq(r2.base_url, "https://api.anthropic.com/v1", "https remote accepted")
-- allow_remote but plaintext http is still refused
local r3, wr3 = load("allow_remote: true\nbackend: openai\nbase_url: http://api.example.com/v1\n")
eq(r3.base_url, "http://127.0.0.1:8989", "plain http remote rejected even with allow_remote")
eq(r3.backend, "libretranslate", "the whole backend falls back, not only base_url")
eq(#wr3, 1, "plain http rejection warns")
-- localhost counts as loopback
local r4 = load("base_url: http://localhost:8989\n")
eq(r4.base_url, "http://localhost:8989", "localhost is loopback")
-- https on loopback is fine too
local r5 = load("base_url: https://127.0.0.1:11434/v1\n")
eq(r5.base_url, "https://127.0.0.1:11434/v1", "https loopback fine")

-- A loopback PREFIX is not a loopback HOST. The plan's prefix match accepted each
-- of these as local, sending every typed sentence off the machine -- with
-- allow_remote false, and over plain http even with it true (design §7.2).
for _, u in ipairs({ "http://127.0.0.1.evil.example/v1", "http://localhost.evil.example/v1",
                     "http://127.0.0.1@evil.example/v1", "http://localhost@evil.example/v1",
                     "http://localhostile.example:8989" }) do
  eq(load("backend: openai\nbase_url: " .. u .. "\n").base_url, "http://127.0.0.1:8989",
     "not loopback without allow_remote: " .. u)
  eq(load("allow_remote: true\nbase_url: " .. u .. "\n").base_url, "http://127.0.0.1:8989",
     "plain http to a remote host refused: " .. u)
end
for _, u in ipairs({ "http://127.0.0.1", "http://localhost", "http://LOCALHOST:8989/x",
                     "https://localhost:8989" }) do
  eq(load("base_url: " .. u .. "\n").base_url, u, "real loopback kept: " .. u)
end

-- curl expands {a,b} and [a-b] globs before it parses the URL, so an authority
-- holding glob syntax is two hosts to curl (Task 5 review, round 1, red): only a
-- host, or a host and a numeric port, may count as loopback. The last case pins
-- the userinfo refusal with a port present.
for _, u in ipairs({ "http://localhost:8989{/,@evil.example/}", "http://localhost:8989{#,@evil.example}",
                     "http://localhost:8989{?,@evil.example/}", "http://localhost:8989[1-2]",
                     "http://127.0.0.1:8989@evil.example/v1" }) do
  eq(load("backend: openai\nbase_url: " .. u .. "\n").base_url, "http://127.0.0.1:8989",
     "not loopback: " .. u)
end

-- backend must name an adapter; anything else warns and the triple falls back
local bk, wbk = load("backend: Anthropic\n")
eq(bk.backend, "libretranslate", "unknown backend falls back")
eq(#wbk, 1, "unknown backend warns")

-- The YAML a person or the installer's template writes: inline comments, quotes,
-- a BOM. Misreading any of these was silent before.
eq(load("model: foo  # the model\n").model, "foo", "inline comment stripped")
eq(load('model: "foo"\n').model, "foo", "double quotes stripped")
eq(load("api_key_account: 'acct'  # keychain account\n").api_key_account, "acct", "quotes and comment stripped")
eq(load('model: "a # b"  # note\n').model, "a # b", "a # inside quotes is not a comment")
eq(load("model: # nothing set\n").model, "", "a value that is only a comment leaves the default")
eq(load("base_url: http://127.0.0.1:8989/#frag\n").base_url, "http://127.0.0.1:8989/#frag",
   "a # with no space before it is not a comment")
eq(load("\239\187\191model: bom\n").model, "bom", "a BOM before the first key is ignored")
-- bools: true or false in any case; anything else warns and keeps the default
eq(load("debug_log: True\n").debug_log, true, "True is true")
local yb, wyb = load("allow_remote: yes\n")
eq(yb.allow_remote, false, "yes is not true: allow_remote stays off")
eq(#wyb, 1, "a non-bool value warns")

-- Task 5 review, round 2. A later invalid bool resets to the default -- it must
-- not leave an earlier "true" standing, which kept cloud on after "no" (yellow 1).
local rb = load("allow_remote: true\nallow_remote: no\n")
eq(rb.allow_remote, false, "an invalid later bool resets to the default")
-- A line that does not parse warns with its number, never its text (§7.3); a
-- full-width colon and a dashed key used to vanish silently (yellow 2).
local _, wl = load("model: ok\nbackend： openai\n\nbase-url: http://127.0.0.1:1\n")
eq(#wl, 2, "two unparseable lines warn")
eq(wl[1], "line 2 not understood", "the warning names the line, not its text")
eq(wl[2], "line 4 not understood", "blank lines still count toward the number")
-- YAML block scalars are not supported: refused, default kept, warned (yellow 2)
local bs, wbs = load("prompt: |\n")
eq(bs.prompt:find("只输出译文") ~= nil, true, "a block scalar leaves the default prompt")
eq(#wbs, 1, "a block scalar warns")
eq(load('model: "|x"\n').model, "|x", "a quoted value starting with | is not a block scalar")
-- an unknown backend takes base_url and model down with it (green 1)
local bt = load("allow_remote: true\nbackend: Anthropic\nbase_url: https://api.anthropic.com/v1\nmodel: m\n")
eq(bt.base_url, "http://127.0.0.1:8989", "unknown backend: base_url falls back too")
eq(bt.model, "", "unknown backend: model falls back too")

-- %s is C's isspace(): under a UTF-8 ctype on macOS it also matches 0xA0, the last
-- byte of U+4E20 -- a prompt ending in that character lost a byte.
local UTF8_CTYPE = os.setlocale("en_US.UTF-8", "ctype") or os.setlocale("C.UTF-8", "ctype")
if not UTF8_CTYPE then io.stderr:write("note: no UTF-8 ctype locale; the trim test ran under C\n") end
eq(load("prompt: \228\184\173\228\184\160\n").prompt, "\228\184\173\228\184\160",
   "prompt keeps a trailing 0xA0 byte under a UTF-8 ctype")
os.setlocale("C", "ctype")

-- api_key_account is kept verbatim and never interpreted
local k = load("api_key_account: anthropic\n")
eq(k.api_key_account, "anthropic", "account name kept verbatim")
---------- feature 003 (backend.md §9): the cloud slot ----------
eq(load(nil).cloud, nil, "no cloud_ keys: no cloud slot")
local GLM = "allow_remote: true\ncloud_backend: openai\n" ..
            "cloud_base_url: https://open.bigmodel.cn/api/paas/v4\ncloud_model: glm-4-flash\n" ..
            "cloud_api_key_account: ime-translate-zhipu\ncloud_timeout_ms: 2500\n"
local g, wg = load(GLM)
eq(#wg, 0, "a valid cloud slot warns nothing")
eq(g.backend, "libretranslate", "the local backend is untouched")
eq(g.base_url, "http://127.0.0.1:8989", "the local base_url is untouched")
eq(g.timeout_ms, 1500, "the local timeout is untouched")
eq(g.api_key_account, "", "the local account is untouched")
eq(g.cloud.backend, "openai", "cloud backend")
eq(g.cloud.base_url, "https://open.bigmodel.cn/api/paas/v4", "cloud base_url")
eq(g.cloud.model, "glm-4-flash", "cloud model")
eq(g.cloud.api_key_account, "ime-translate-zhipu", "cloud account")
eq(g.cloud.timeout_ms, 2500, "cloud timeout")
eq(g.cloud.allow_remote, true, "allow_remote is shared")
eq(g.cloud.temperature, 0.2, "an unset cloud key takes the default")
assert(g.cloud.prompt:find("只输出译文"), "the cloud slot gets the default prompt")
eq(g.cloud.cloud, nil, "the cloud slot holds no slot of its own")
for key in pairs(load(nil)) do
  eq(g.cloud[key] ~= nil, true, "the cloud slot has " .. key)
end
-- unset cloud keys take the defaults, not the local slot's values
local u = load("timeout_ms: 900\nmodel: local-m\ncloud_backend: libretranslate\ncloud_base_url: http://127.0.0.1:8989\n")
eq(u.cloud.timeout_ms, 1500, "cloud timeout is the default, not the local 900")
eq(u.cloud.model, "", "cloud model is the default, not the local one")
-- D9, the user's decision: a cloud slot must name its server
local nu, wnu = load("allow_remote: true\ncloud_backend: anthropic\ncloud_api_key_account: a\n")
eq(nu.cloud, nil, "no cloud_base_url: no cloud slot")
eq(#wnu, 1, "the drop warns once")
assert(wnu[1]:find("cloud_base_url"), "the warning names cloud_base_url")
eq(nu.backend, "libretranslate", "the local slot is untouched")
-- the shared keys come from the unprefixed ones
local sh = load("max_chars: 50\ndebug_log: true\ncloud_backend: libretranslate\ncloud_base_url: http://127.0.0.1:8989\n")
eq(sh.cloud.max_chars, 50, "max_chars is shared")
eq(sh.cloud.debug_log, true, "debug_log is shared")
eq(load("max_chars: 0\ncloud_backend: libretranslate\ncloud_base_url: http://127.0.0.1:8989\n").cloud.max_chars, 2000,
   "the shared max_chars is range-checked before it is shared")
-- a cloud slot that fails a check is dropped, never replaced by translate
local nr, wnr = load("cloud_backend: openai\ncloud_base_url: https://open.bigmodel.cn/api/paas/v4\n")
eq(nr.cloud, nil, "remote cloud without allow_remote: no cloud slot")
eq(#wnr, 1, "the drop warns once")
eq(nr.backend, "libretranslate", "the local slot is untouched by the drop")
local ht, wht = load("allow_remote: true\ncloud_backend: openai\ncloud_base_url: http://api.example.com/v1\n")
eq(ht.cloud, nil, "plain http cloud: no cloud slot")
eq(#wht, 1, "the plain http drop warns once")
local ub, wub = load("cloud_backend: Openai\n")
eq(ub.cloud, nil, "unknown cloud backend: no cloud slot")
eq(#wub, 1, "the unknown cloud backend warns once")
for _, w in ipairs({ wnr[1], wht[1], wub[1] }) do
  assert(not w:find("bigmodel") and not w:find("example") and not w:find("Openai"),
         "a drop warning names no value: " .. w)
end
-- the range check resets, as for the local slot
local ct, wct = load("cloud_backend: libretranslate\ncloud_base_url: http://127.0.0.1:8989\ncloud_timeout_ms: 99999\n")
eq(ct.cloud.timeout_ms, 2500, "a cloud timeout above the ceiling is capped at 2500 (D10)")
eq(load("cloud_backend: libretranslate\ncloud_base_url: http://127.0.0.1:8989\ncloud_timeout_ms: 99\n").cloud.timeout_ms,
   1500, "a cloud timeout below the floor resets to the default")
eq(#wct, 1, "the reset warns")
-- cloud_ keys with no cloud_backend: no slot, one warning
local nb, wnb = load("cloud_model: m\ncloud_timeout_ms: 2000\n")
eq(nb.cloud, nil, "no cloud_backend: no cloud slot")
eq(#wnb, 1, "cloud keys without cloud_backend warn once")
eq(nb.model, "", "a cloud_ key never lands in the local slot")
-- a shared key under the prefix is unknown, not quietly shared
local sk, wsk = load("cloud_backend: libretranslate\ncloud_base_url: http://127.0.0.1:8989\ncloud_allow_remote: true\n")
eq(#wsk, 1, "cloud_allow_remote is an unknown key")
assert(wsk[1]:find("cloud_allow_remote"), "the warning names the prefixed key")
eq(sk.cloud.allow_remote, false, "cloud_allow_remote does not turn remote on")
-- the prefix is exact
local _, wpx = load("cloudbackend: openai\n")
eq(#wpx, 1, "cloudbackend is an unknown key")
-- a bad cloud value warns under its prefixed name
local _, wnn = load("cloud_backend: libretranslate\ncloud_base_url: http://127.0.0.1:8989\ncloud_timeout_ms: abc\n")
eq(#wnn, 1, "a non-numeric cloud value warns")
assert(wnn[1]:find("cloud_timeout_ms"), "the warning names cloud_timeout_ms")
-- Task 1 review, round 1, yellow: prompt, temperature and max_tokens are slot
-- keys too. Set on the local slot, the cloud slot does not inherit them ...
local lk = load("prompt: local prompt\ntemperature: 0.7\nmax_tokens: 99\ncloud_backend: libretranslate\ncloud_base_url: http://127.0.0.1:8989\n")
eq(lk.cloud.temperature, 0.2, "cloud temperature is the default, not the local 0.7")
eq(lk.cloud.max_tokens, 1024, "cloud max_tokens is the default, not the local 99")
assert(lk.cloud.prompt:find("只输出译文"), "cloud prompt is the default, not the local one")
-- ... and set under cloud_, they are read into the cloud slot only
local ck, wck = load("cloud_backend: libretranslate\ncloud_base_url: http://127.0.0.1:8989\ncloud_prompt: cloud prompt\n" ..
                     "cloud_temperature: 0.5\ncloud_max_tokens: 2048\n")
eq(#wck, 0, "cloud_prompt, cloud_temperature and cloud_max_tokens are known keys")
eq(ck.cloud.prompt, "cloud prompt", "cloud_prompt is read")
eq(ck.cloud.temperature, 0.5, "cloud_temperature is read")
eq(ck.cloud.max_tokens, 2048, "cloud_max_tokens is read")
eq(ck.temperature, 0.2, "the local temperature is untouched")
eq(ck.max_tokens, 1024, "the local max_tokens is untouched")
-- green 1: the warnings say which slot they are about
assert(wct[1]:find("cloud_timeout_ms"), "the reset warning names cloud_timeout_ms")
assert(wnr[1]:find("^cloud slot dropped: "), "the drop warning names the cloud slot")
print(("test_config: %d assertions OK"):format(n))

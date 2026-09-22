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
local o2 = load("timeout_ms: 99999\n"); eq(o2.timeout_ms, 1500, "timeout above ceiling")
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
print(("test_config: %d assertions OK"):format(n))

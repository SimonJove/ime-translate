package.path = package.path .. ";rime/lua/?.lua"
-- Feature 005 (backend.md §8.3): finished translations, most recent first
local cache = require("ime_translate.cache")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

local c = cache.new(3)
eq(c:get("local", "你好"), nil, "a miss")
c:put("local", "你好", "Hello")
eq(c:get("local", "你好"), "Hello", "get after put")
eq(c:get("cloud", "你好"), nil, "the slot is part of the key")
c:put("cloud", "你好", "Hi")
eq(c:get("cloud", "你好"), "Hi", "the other slot has its own entry")
eq(c:get("local", "你好"), "Hello", "and the first is untouched")
-- slot and draft cannot run into each other: "ab" + "c" is not "a" + "bc"
-- (005 Task 3 review, green: the first version of this case could not fail)
c:put("ab", "c", "x")
eq(c:get("a", "bc"), nil, "slot and draft cannot run into each other")

-- capacity: the least recently used goes first; a get refreshes
local d = cache.new(3)
d:put("local", "1", "one"); d:put("local", "2", "two"); d:put("local", "3", "three")
eq(d:get("local", "1"), "one", "1 read: now the most recent")
d:put("local", "4", "four")
eq(d:get("local", "2"), nil, "2, the least recent, was evicted")
eq(d:get("local", "1"), "one", "1 survived: the get refreshed it")
eq(d:get("local", "3"), "three", "3 survived")
eq(d:get("local", "4"), "four", "4 is in")
-- a put over an existing key replaces it and takes no second place
d:put("local", "4", "FOUR")
eq(d:get("local", "4"), "FOUR", "a put replaces")
eq(d:get("local", "1"), "one", "and evicts nothing")
eq(d:get("local", "3"), "three", "nothing at all")

-- two caches share nothing
local e = cache.new(3)
eq(e:get("local", "1"), nil, "a new cache is empty")

-- 32 is the size the design names; the 33rd put evicts the first
local f = cache.new(32)
for i = 1, 33 do f:put("local", tostring(i), "t" .. i) end
eq(f:get("local", "1"), nil, "the 33rd put evicts the first")
eq(f:get("local", "2"), "t2", "the second survives")

print(("test_cache: %d assertions OK"):format(n))

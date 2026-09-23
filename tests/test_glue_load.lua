package.path = package.path .. ";rime/lua/?.lua"
-- The glue modules do only require/return at the top level and touch no rime
-- global, so they must load headless.
local names = { "ime_translate_shared", "ime_translate_processor" }
for _, name in ipairs(names) do
  local ok, m = pcall(require, name)
  assert(ok, ("fail to load %s: %s"):format(name, tostring(m)))
  assert(type(m) == "function" or type(m) == "table",
         name .. " must export func/table")
end
-- shared must not read files or spawn subprocesses at load time
local shared = require("ime_translate_shared")
assert(shared.loaded == false, "shared must be lazy: loaded=false before ensure()")
assert(shared.settings == nil, "shared must not read config at load time")
assert(shared.cache == nil, "no cache before ensure() (feature 005)")
-- session state must never appear on the module singleton
assert(shared.fsm == nil, "no fsm on the module singleton")
assert(shared.phase == nil, "no phase on the module singleton")
-- D1: the display translator and the filter are gone
for _, gone in ipairs({ "ime_translate_translator", "ime_translate_filter" }) do
  assert(not pcall(require, gone), gone .. " must not exist (decision D1)")
end
print("test_glue_load: 2 modules OK, shared is lazy and stateless")

-- Feature 005 (backend.md §8.3): finished translations, keyed by the slot that
-- answered and the exact draft, the most recently used first. Pure: no IO, no
-- rime global. One cache per Lua state lives in ime_translate_shared; it is
-- process-wide by §6.1's test -- the same draft sent to the same slot has the
-- same translation in any input box.
local M = {}

local Cache = {}
Cache.__index = Cache

-- A length prefix keeps slot and draft apart whatever bytes the draft holds
local function key(slot, draft) return #slot .. ":" .. slot .. draft end

function M.new(size)
  return setmetatable({ size = size, map = {}, order = {} }, Cache)
end

-- Move k to the most recent end of the order
local function touch(self, k)
  for i, v in ipairs(self.order) do
    if v == k then table.remove(self.order, i); break end
  end
  self.order[#self.order + 1] = k
end

function Cache:get(slot, draft)
  local k = key(slot, draft)
  local text = self.map[k]
  if text then touch(self, k) end
  return text
end

function Cache:put(slot, draft, text)
  local k = key(slot, draft)
  self.map[k] = text
  touch(self, k)
  while #self.order > self.size do
    self.map[table.remove(self.order, 1)] = nil
  end
end

return M

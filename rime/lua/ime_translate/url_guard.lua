-- Feature 005 (backend.md §7.5): the URL guard, used by the libretranslate
-- adapter only. Pure: no IO, no rime global. translate glues a URL to its
-- neighbours and can leave the Chinese after it untranslated, so each URL goes
-- as a placeholder X_1, X_2, ... and comes back after. A URL is a run of the
-- ASCII characters RFC 3986 allows, so it ends at a space or at Chinese.
local M = {}

local URL_CHARS = "[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]"

-- Sentence punctuation after a URL is the sentence's, and so is a ) that
-- closes nothing inside the URL.
local function url_end(u)
  while true do
    local last = u:sub(-1)
    if last:find("^[.,;:!?']$") then
      u = u:sub(1, -2)
    elseif last == ")" and select(2, u:gsub("%(", "")) < select(2, u:gsub("%)", "")) then
      u = u:sub(1, -2)
    else
      return u
    end
  end
end

-- text -> sent, urls. With no URL, or a text that already holds anything
-- unguard could read as a placeholder -- X_<digit> anywhere, MAX_1 included,
-- since unguard also takes one glued to a word -- the text goes as is and
-- urls is nil.
function M.guard(text)
  if text:find("X_%d") then return text, nil end
  local urls, out, pos = {}, {}, 1
  while true do
    local s, e = text:find("https?://" .. URL_CHARS .. "+", pos)
    if not s then break end
    local u = url_end(text:sub(s, e))
    urls[#urls + 1] = u
    -- A placeholder glued to a word would read as part of it: space it off
    local sep = text:sub(s - 1, s - 1):find("^%w$") and " " or ""
    out[#out + 1] = text:sub(pos, s - 1) .. sep .. "X_" .. #urls
    pos = s + #u
  end
  if #urls == 0 then return text, nil end
  out[#out + 1] = text:sub(pos)
  return table.concat(out), urls
end

-- Each placeholder must come back exactly once; otherwise nil, and the
-- translation fails rather than commit a URL altered or lost. translate may
-- glue a placeholder to the word before it, as it glues a bare URL (§7.5), so
-- one found after a letter or digit gets its space back.
function M.unguard(out, urls)
  for i, u in ipairs(urls) do
    local pat = "(%w?)X_" .. i .. "%f[%W]"
    local _, count = out:gsub(pat, "")
    if count ~= 1 then return nil end
    out = out:gsub(pat, function(pre) return pre .. (pre ~= "" and " " or "") .. u end)
  end
  return out
end

return M

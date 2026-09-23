package.path = package.path .. ";rime/lua/?.lua"
-- Feature 005 (backend.md §7.5): the URL guard. translate glues a URL to its
-- neighbours, so libretranslate is sent X_n placeholders and the URLs are put
-- back after. Through translate: test_backend.lua.
local url_guard = require("ime_translate.url_guard")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

local G1 = "https://github.com/foo/bar"
local sent, urls = url_guard.guard("看一下 " .. G1 .. " 这个仓库")
eq(sent, "看一下 X_1 这个仓库", "one URL becomes X_1")
eq(#urls, 1, "one URL listed"); eq(urls[1], G1, "the URL as typed")
sent, urls = url_guard.guard("文档在https://example.com/a?b=1里面")
eq(sent, "文档在X_1里面", "a URL glued to Chinese on both sides")
eq(urls[1], "https://example.com/a?b=1", "the URL stops at the Chinese")
sent, urls = url_guard.guard("打开 http://a.com 和 https://b.com/x_(y) 看看")
eq(sent, "打开 X_1 和 X_2 看看", "two URLs, numbered in order")
eq(urls[2], "https://b.com/x_(y)", "balanced parentheses stay in the URL")
sent, urls = url_guard.guard("见 https://a.com/x. 以及 (https://b.com)!")
eq(sent, "见 X_1. 以及 (X_2)!", "trailing punctuation and an unbalanced ) stay outside")
eq(urls[1], "https://a.com/x", "no trailing dot"); eq(urls[2], "https://b.com", "no trailing paren")
sent, urls = url_guard.guard("没有链接")
eq(sent, "没有链接", "no URL: the text as is"); eq(urls, nil, "no URL: no list")
sent, urls = url_guard.guard("X_1 和 https://a.com")
eq(sent, "X_1 和 https://a.com", "a text already holding X_1 is sent unguarded"); eq(urls, nil, "and has no list")
-- 005 Task 2 review, round 2, red: unguard takes a placeholder glued to a word,
-- so MAX_1 in the draft could pass for X_1. Such a draft goes unguarded.
sent, urls = url_guard.guard("设置 MAX_1 见 https://a.com")
eq(sent, "设置 MAX_1 见 https://a.com", "a draft holding MAX_1 is sent unguarded"); eq(urls, nil, "with no list")

eq(url_guard.unguard("Take a look at X_1 this repo", { G1 }), "Take a look at " .. G1 .. " this repo", "unguard restores")
eq(url_guard.unguard("A X_2 and X_1.", { "https://a.com", "https://b.com/%1" }),
   "A https://b.com/%1 and https://a.com.", "order in the output is free; % in a URL is literal")
eq(url_guard.unguard("nothing here", { G1 }), nil, "a missing placeholder fails")
eq(url_guard.unguard("X_1 X_1", { G1 }), nil, "a doubled placeholder fails")
eq(url_guard.unguard("X_12", { G1 }), nil, "X_12 is not X_1")
eq(url_guard.unguard("in X_1", { G1 }), "in " .. G1, "a spaced placeholder keeps its one space")
eq(url_guard.unguard("inX_1.", { G1 }), "in " .. G1 .. ".", "a placeholder glued to a word gets its space back")
eq(url_guard.unguard("X_1a", { G1 }), nil, "X_1 followed by a letter is not X_1")
-- 005 Task 2 review, yellow: a URL right after a letter is spaced off, so its
-- placeholder is not read as part of the word
sent, urls = url_guard.guard("seehttps://a.com 看看")
eq(sent, "see X_1 看看", "a URL after a letter: the placeholder is spaced off")
eq(url_guard.unguard("See X_1 look", urls), "See https://a.com look", "and comes back")
sent = url_guard.guard("v2https://a.com")
eq(sent, "v2 X_1", "after a digit too")
sent = url_guard.guard("看https://a.com")
eq(sent, "看X_1", "after Chinese: no space added")

print(("test_url_guard: %d assertions OK"):format(n))

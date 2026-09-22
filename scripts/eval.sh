#!/bin/bash
# Evaluate the default backend, translate (the libretranslate adapter), on
# eval/sentences.txt: one request per sentence, as the IME sends it; the
# translation and the time; then P50 and P95 (nearest rank).
# usage: scripts/eval.sh [base_url]      default http://127.0.0.1:8989
set -euo pipefail
cd "$(dirname "$0")/.."
BASE="${1:-http://127.0.0.1:8989}"
OUT="eval/results-translate.md"
python3 - "$BASE" "$OUT" <<'PY'
import json, math, sys, time, urllib.request
base, out = sys.argv[1], sys.argv[2]
# No proxy: the IME's curl goes straight to the loopback service, while urllib
# would take the macOS system proxy even for 127.0.0.1 (seen with a proxy app
# running, 001 Task 11).
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
rows, times = [], []
for line in open("eval/sentences.txt", encoding="utf-8"):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    cat, src = line.split("\t", 1)
    body = json.dumps({"q": src, "source": "zh", "target": "en", "format": "text"}).encode()
    req = urllib.request.Request(base + "/translate", data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.monotonic()
    try:
        with opener.open(req, timeout=10) as r:
            text = json.load(r).get("translatedText", "")
    except Exception as e:
        text = "ERROR " + type(e).__name__
    ms = round((time.monotonic() - t0) * 1000)
    rows.append((cat, src, text, ms))
    if not text.startswith("ERROR "):
        times.append(ms)               # a failed request is no latency sample
errors = len(rows) - len(times)
def pct(p):
    s = sorted(times)
    return s[max(0, math.ceil(p / 100 * len(s)) - 1)] if s else "n/a"
cell = lambda s: s.replace("|", "\\|").replace("\n", " ")
with open(out, "w", encoding="utf-8") as f:
    f.write(f"# Evaluation: translate ({base})\n\n")
    f.write("| # | category | source | translation | ms | verdict |\n")
    f.write("|---|---|---|---|---|---|\n")
    for i, (cat, src, text, ms) in enumerate(rows, 1):
        f.write(f"| {i} | {cat} | {cell(src)} | {cell(text)} | {ms} | |\n")
    f.write(f"\n{len(rows)} sentences, {errors} failed. P50 {pct(50)} ms, P95 {pct(95)} ms"
            " (over the successful requests).\n")
print(f"wrote {out}: {len(rows)} sentences, {errors} failed, P50 {pct(50)} ms, P95 {pct(95)} ms")
sys.exit(1 if errors else 0)
PY

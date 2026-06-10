#!/usr/bin/env bash
# agent1_news.sh — crawl MBSE news from Google News RSS + INCOSE
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/skills.sh"

OUTPUT="/tmp/news_results.json"
TSV_TMP=$(mktemp)

RSS_SOURCES=(
    "https://news.google.com/rss/search?q=MBSE+systems+engineering&hl=en&gl=US&ceid=US:en"
    "https://news.google.com/rss/search?q=SysML+digital+engineering&hl=en&gl=US&ceid=US:en"
)

echo "[agent1] Fetching news sources..." >&2

# ── Step 1: fetch RSS feeds ────────────────────────────────────────────────
for src in "${RSS_SOURCES[@]}"; do
    echo "[agent1] RSS: $src" >&2
    fetch_rss "$src" >> "$TSV_TMP" 2>/dev/null || \
        echo "[agent1] WARN: failed to fetch $src" >&2
done

# ── Step 2: INCOSE news page ───────────────────────────────────────────────
echo "[agent1] Fetching INCOSE..." >&2
incose_html=$(web_fetch "https://www.incose.org/news-and-events/news") || \
    incose_html=""

if [[ -n "$incose_html" ]]; then
    echo "$incose_html" | python3 - "$SCRIPT_DIR/cache/seen_urls.txt" <<'PYEOF' >> "$TSV_TMP"
import sys, re
cache_file = sys.argv[1] if len(sys.argv) > 1 else ""
html = sys.stdin.read()
cached = set()
try:
    with open(cache_file) as f:
        cached = set(f.read().splitlines())
except:
    pass
seen = set()
pattern = r'<a[^>]+href=["\']([^"\']+)["\'][^>]*>\s*([^<]{20,})\s*</a>'
for href, text in re.findall(pattern, html, re.DOTALL):
    text = re.sub(r'\s+',' ', text).strip()
    if not href.startswith('http'):
        href = 'https://www.incose.org' + href
    if href in seen or href in cached:
        continue
    if re.search(r'MBSE|SysML|systems.engineering|INCOSE|model.based', text, re.I):
        seen.add(href)
        print(f"{text}|{href}|")
PYEOF
fi

# ── Step 3: filter keywords ────────────────────────────────────────────────
filtered=$(filter_keywords "$TSV_TMP" \
    MBSE SysML UAF "digital.twin" "systems.engineering" \
    Cameo model-based INCOSE DoDAF UPDM Capella)

# ── Step 4: deduplicate against cache ─────────────────────────────────────
echo "$filtered" > "$TSV_TMP"
deduplicate "$TSV_TMP"

# ── Step 5: build JSON array ───────────────────────────────────────────────
python3 - "$TSV_TMP" <<'PYEOF' > "$OUTPUT"
import sys, json, re

items = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        parts = line.split('|')
        title = parts[0].strip() if len(parts) > 0 else ''
        url   = parts[1].strip() if len(parts) > 1 else ''
        date  = parts[2].strip() if len(parts) > 2 else ''
        # Strip " - Source Name" suffix Google News adds
        title = re.sub(r'\s+-\s+[^-]{3,40}$', '', title).strip()
        if title and url:
            items.append({'title': title, 'url': url, 'date': date,
                          'source': 'news', 'summary': ''})

print(json.dumps(items, ensure_ascii=False, indent=2))
PYEOF

count=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(len(d))")
echo "[agent1] Done — $count new news items → $OUTPUT" >&2
cat "$OUTPUT"
rm -f "$TSV_TMP"

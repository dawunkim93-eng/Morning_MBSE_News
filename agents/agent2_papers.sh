#!/usr/bin/env bash
# agent2_papers.sh — crawl MBSE papers from arXiv + Semantic Scholar
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/skills.sh"

OUTPUT="/tmp/papers_results.json"
ARXIV_TMP=$(mktemp)
SEMANTIC_TMP=$(mktemp)

echo "[agent2] Fetching paper sources (parallel)..." >&2

# ── Step 1: fetch arXiv + Semantic Scholar concurrently ───────────────────
(
    arxiv_url="https://export.arxiv.org/api/query?search_query=all:MBSE+OR+all:SysML+OR+all:%22systems+engineering%22&sortBy=submittedDate&sortOrder=descending&max_results=15"
    echo "[agent2] arXiv: $arxiv_url" >&2
    xml=$(web_fetch "$arxiv_url") || exit 0
    echo "$xml" | python3 - <<'PYEOF' > "$ARXIV_TMP"
import sys, json, xml.etree.ElementTree as ET, re
ns = {'atom': 'http://www.w3.org/2005/Atom'}
try:
    root = ET.fromstring(sys.stdin.read())
    items = []
    for entry in root.findall('atom:entry', ns):
        t  = entry.find('atom:title', ns)
        l  = entry.find('atom:id', ns)
        p  = entry.find('atom:published', ns)
        s  = entry.find('atom:summary', ns)
        title   = t.text.strip().replace('\n',' ') if t is not None else ''
        url     = l.text.strip() if l is not None else ''
        date    = p.text[:10] if p is not None else ''
        abstract= s.text.strip().replace('\n',' ') if s is not None else ''
        if title and url:
            items.append({'title':title,'url':url,'date':date,
                          'abstract':abstract,'source':'arxiv','citation_count':99})
    print(json.dumps(items, ensure_ascii=False))
except Exception as e:
    print(f'[agent2-arxiv] error: {e}', file=sys.stderr)
    print('[]')
PYEOF
) &
PID_ARXIV=$!

(
    sem_url="https://api.semanticscholar.org/graph/v1/paper/search?query=model-based+systems+engineering&fields=title,abstract,authors,year,citationCount,externalIds&limit=10"
    echo "[agent2] Semantic Scholar: $sem_url" >&2
    json=$(web_fetch "$sem_url") || exit 0
    echo "$json" | python3 - <<'PYEOF' > "$SEMANTIC_TMP"
import sys, json
try:
    d = json.loads(sys.stdin.read())
    items = []
    for p in d.get('data', []):
        title   = p.get('title', '')
        year    = str(p.get('year', '')) if p.get('year') else ''
        abstract= (p.get('abstract') or '').replace('\n', ' ')
        cites   = p.get('citationCount', 0) or 0
        ext_ids = p.get('externalIds', {}) or {}
        doi = ext_ids.get('DOI','')
        url = f"https://doi.org/{doi}" if doi else f"https://www.semanticscholar.org/paper/{p.get('paperId','')}"
        if title:
            items.append({'title':title,'url':url,'date':year,
                          'abstract':abstract,'source':'semantic','citation_count':cites})
    print(json.dumps(items, ensure_ascii=False))
except Exception as e:
    print(f'[agent2-semantic] error: {e}', file=sys.stderr)
    print('[]')
PYEOF
) &
PID_SEMANTIC=$!

wait $PID_ARXIV $PID_SEMANTIC
echo "[agent2] Both fetch jobs done" >&2

# ── Step 2: merge, filter, citation noise filter, deduplicate ─────────────
python3 - "$ARXIV_TMP" "$SEMANTIC_TMP" "$SCRIPT_DIR/cache/seen_urls.txt" <<'PYEOF' > "$OUTPUT"
import sys, json, re

def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return []

def load_cache(path):
    try:
        with open(path) as f:
            return set(f.read().splitlines())
    except:
        return set()

KEYWORDS = re.compile(
    r'MBSE|SysML|UAF|digital.twin|systems.engineering|'
    r'Cameo|model.based|INCOSE|DoDAF|UPDM|Capella', re.I)

cache = load_cache(sys.argv[3])
all_items = load(sys.argv[1]) + load(sys.argv[2])

seen_urls   = set()
seen_titles = set()
results     = []

for item in all_items:
    title    = item.get('title','')
    url      = item.get('url','')
    abstract = item.get('abstract','')
    cites    = item.get('citation_count', 0) or 0

    # Citation noise filter (keep arXiv always; filter Semantic Scholar with <2)
    if item.get('source') == 'semantic' and cites < 2:
        continue

    # Keyword filter
    if not KEYWORDS.search(title + ' ' + abstract):
        continue

    # Cache + dedup
    if url in cache or url in seen_urls:
        continue
    if title in seen_titles:
        continue

    seen_urls.add(url)
    seen_titles.add(title)
    results.append(item)

print(json.dumps(results, ensure_ascii=False, indent=2))
PYEOF

count=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(len(d))")
echo "[agent2] Done — $count new paper items → $OUTPUT" >&2
cat "$OUTPUT"
rm -f "$ARXIV_TMP" "$SEMANTIC_TMP"

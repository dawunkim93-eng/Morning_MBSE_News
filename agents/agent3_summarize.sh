#!/usr/bin/env bash
# agent3_summarize.sh — Claude API summarizer, tagger, ranker
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/skills.sh"

NEWS_IN="/tmp/news_results.json"
PAPERS_IN="/tmp/papers_results.json"
OUTPUT="/tmp/summary_results.json"
MAX_NEWS="${MAX_NEWS_ITEMS:-5}"
MAX_PAPERS="${MAX_PAPER_ITEMS:-5}"

echo "[agent3] Summarizing items with Claude..." >&2

python3 - "$NEWS_IN" "$PAPERS_IN" "$OUTPUT" \
         "$MAX_NEWS" "$MAX_PAPERS" \
         "${ANTHROPIC_API_KEY:-}" \
         "${CLAUDE_MODEL:-claude-haiku-4-5-20251001}" \
         "${DRY_RUN:-0}" <<'PYEOF'
import sys, json, re, urllib.request, urllib.error

news_path, papers_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]
max_news, max_papers = int(sys.argv[4]), int(sys.argv[5])
api_key   = sys.argv[6]
model     = sys.argv[7]
dry_run   = sys.argv[8] == "1"

KEYWORDS = {
    'SysML':   re.compile(r'SysML|UML', re.I),
    'UAF':     re.compile(r'UAF|DoDAF|UPDM|NATO', re.I),
    'Tool':    re.compile(r'Cameo|Capella|Rhapsody|MagicDraw|tool|software', re.I),
    'Standard':re.compile(r'standard|ISO|IEEE|OMG|specification', re.I),
    'Research':re.compile(r'survey|framework|ontology|formal|method', re.I),
    'Industry':re.compile(r'industr|defense|aerospace|automotive|enterprise', re.I),
}

def categorize(text: str) -> str:
    for cat, pat in KEYWORDS.items():
        if pat.search(text):
            return cat
    return 'Research'

def keyword_score(text: str) -> int:
    core = re.compile(r'\bMBSE\b|\bSysML\b|\bUAF\b', re.I)
    related = re.compile(
        r'systems.engineering|model.based|digital.twin|INCOSE|Cameo|Capella', re.I)
    return len(core.findall(text)) * 3 + len(related.findall(text))

def claude_summarize(title: str, body: str) -> str:
    if dry_run or not api_key:
        return f"• [DRY-RUN] {title[:80]}\n• 요약 생략\n• (API 키 없음)"
    text = f"제목: {title}\n\n내용: {body[:2000]}"
    payload = json.dumps({
        "model": model,
        "max_tokens": 300,
        "system": "당신은 MBSE 전문가입니다. 핵심만 3줄로 요약하세요. 각 줄은 •로 시작하세요.",
        "messages": [{"role": "user", "content": text}]
    }).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            d = json.loads(resp.read())
            return d["content"][0]["text"].strip()
    except Exception as e:
        print(f"[agent3] summarize error: {e}", file=sys.stderr)
        return f"• 요약 실패: {e}"

def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return []

news   = load(news_path)
papers = load(papers_path)

results = {"news": [], "papers": []}

print(f"[agent3] Summarizing {len(news)} news, {len(papers)} papers...", file=sys.stderr)

for item in news:
    body = item.get('summary', '') or item.get('abstract', '')
    text = f"{item['title']} {body}"
    score = min(keyword_score(text), 10)
    summary = claude_summarize(item['title'], body)
    results["news"].append({
        **item,
        "summary":  summary,
        "category": categorize(text),
        "score":    score,
    })

for item in papers:
    body = item.get('abstract', '')
    text = f"{item['title']} {body}"
    score = min(keyword_score(text), 10)
    summary = claude_summarize(item['title'], body)
    results["papers"].append({
        **item,
        "summary":  summary,
        "category": categorize(text),
        "score":    score,
    })

# Sort by score descending, keep top N
results["news"]   = sorted(results["news"],   key=lambda x: x["score"], reverse=True)[:max_news]
results["papers"] = sorted(results["papers"], key=lambda x: x["score"], reverse=True)[:max_papers]

with open(output_path, "w") as f:
    json.dump(results, f, ensure_ascii=False, indent=2)

n = len(results["news"])
p = len(results["papers"])
print(f"[agent3] Done — top {n} news, top {p} papers → {output_path}", file=sys.stderr)
PYEOF

echo "[agent3] Summary written to $OUTPUT" >&2
cat "$OUTPUT"

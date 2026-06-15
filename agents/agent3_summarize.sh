#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 파일    : agents/agent3_summarize.sh
# 설명    : Claude API 요약·분류·랭킹 에이전트.
#           Phase 1 에서 수집된 뉴스와 논문 JSON을 읽어 각 항목을 Claude API로
#           3줄 요약하고, 카테고리를 부여하며, 관련도 점수로 내림차순 정렬한다.
#           상위 N건만 유지해 /tmp/summary_results.json 으로 출력한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — Claude API 요약, 카테고리 분류, 점수 랭킹 구현
# ─────────────────────────────────────────────────────────────────────────────
#
# 입력:
#   /tmp/news_results.json   (agent1 출력)
#   /tmp/papers_results.json (agent2 출력)
#
# 출력:
#   stdout : JSON → /tmp/summary_results.json
#   stderr : 진행 상황 로그

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/skills.sh"

# ── 설정 ────────────────────────────────────────────────────────────────────
NEWS_IN="$SHARED_TMP/news_results.json"    # agent1 출력 파일
PAPERS_IN="$SHARED_TMP/papers_results.json" # agent2 출력 파일
OUTPUT="$SHARED_TMP/summary_results.json"  # agent4 가 읽을 결과 파일

MAX_NEWS="${MAX_NEWS_ITEMS:-5}"           # 최종 전송할 뉴스 최대 건수
MAX_PAPERS="${MAX_PAPER_ITEMS:-5}"        # 최종 전송할 논문 최대 건수

echo "[agent3] Claude API로 요약 중..." >&2

# ── 핵심 로직: Python 인라인 스크립트 ─────────────────────────────────────────
# 복잡한 JSON 처리와 HTTP 요청을 Python으로 수행
python3 - "$NEWS_IN" "$PAPERS_IN" "$OUTPUT" \
         "$MAX_NEWS" "$MAX_PAPERS" \
         "${OPENROUTER_API_KEY:-}" \
         "${ANTHROPIC_API_KEY:-}" \
         "${CLAUDE_MODEL:-claude-haiku-4-5-20251001}" \
         "${DRY_RUN:-0}" <<'PYEOF'
import sys, json, re, urllib.request, urllib.error
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

# ── 인자 파싱 ─────────────────────────────────────────────────────────────────
news_path, papers_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]
max_news      = int(sys.argv[4])
max_papers    = int(sys.argv[5])
or_key        = sys.argv[6]
anthropic_key = sys.argv[7]
model         = sys.argv[8]
dry_run       = sys.argv[9] == "1"

# ── KST 날짜 윈도우: 어제 07:00 KST ~ 오늘 07:00 KST ────────────────────────
KST        = timezone(timedelta(hours=9))
now_kst    = datetime.now(KST)
today_7am  = now_kst.replace(hour=7, minute=0, second=0, microsecond=0)
window_end = today_7am if now_kst >= today_7am else today_7am - timedelta(days=1)
window_start = window_end - timedelta(days=1)

report_date    = window_end.strftime('%Y-%m-%d')
report_date_kr = f"{window_end.year}년 {window_end.month}월 {window_end.day}일"

# ── 날짜 유틸리티 ─────────────────────────────────────────────────────────────
def parse_date(s: str):
    if not s: return None
    try: return parsedate_to_datetime(s)
    except: pass
    try:
        dt = datetime.fromisoformat(s.replace('Z', '+00:00'))
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except: pass
    try:
        dt = datetime.strptime(s[:10], '%Y-%m-%d')
        return dt.replace(tzinfo=timezone.utc)
    except: pass
    return None

def date_to_kr(s: str) -> str:
    dt = parse_date(s)
    return f"{dt.month}월 {dt.day}일" if dt else s

def in_window(item: dict) -> bool:
    dt = parse_date(item.get('date', ''))
    return dt is not None and window_start <= dt <= window_end

# ── 카테고리·키워드 점수 ──────────────────────────────────────────────────────
CATEGORIES = {
    'SysML':    re.compile(r'SysML|UML', re.I),
    'UAF':      re.compile(r'UAF|DoDAF|UPDM|NATO', re.I),
    'Tool':     re.compile(r'Cameo|Capella|Rhapsody|MagicDraw|software|tool', re.I),
    'Standard': re.compile(r'standard|ISO|IEEE|OMG|specification', re.I),
    'Research': re.compile(r'survey|framework|ontology|formal|method', re.I),
    'Industry': re.compile(r'industr|defense|aerospace|automotive|enterprise', re.I),
}
def categorize(text):
    for cat, pat in CATEGORIES.items():
        if pat.search(text): return cat
    return 'Research'

def keyword_score(text):
    core    = re.compile(r'\bMBSE\b|\bSysML\b|\bUAF\b', re.I)
    related = re.compile(r'systems.engineering|model.based|digital.twin|INCOSE|Cameo|Capella', re.I)
    return len(core.findall(text)) * 3 + len(related.findall(text))

# ── AI 요약 (OpenRouter → Anthropic → 더미) ──────────────────────────────────
def ai_summarize(title: str, body: str) -> str:
    if dry_run:
        return f"• [DRY-RUN] {title[:80]}"
    system_prompt = "MBSE 전문가로서 핵심만 3~5줄 한국어로 요약하세요. 각 줄은 •로 시작하세요."
    user_content  = f"제목: {title}\n\n내용: {body[:2000]}"
    if or_key:
        payload = json.dumps({
            "model": "google/gemma-4-31b-it:free",
            "messages": [{"role": "system", "content": system_prompt},
                         {"role": "user",   "content": user_content}],
            "max_tokens": 400
        }).encode()
        req = urllib.request.Request(
            "https://openrouter.ai/api/v1/chat/completions", data=payload,
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {or_key}"},
            method="POST")
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read())["choices"][0]["message"]["content"].strip()
        except urllib.error.HTTPError as e:
            print(f"[agent3] OpenRouter 오류: HTTP {e.code}: {e.read().decode()[:150]}", file=sys.stderr)
        except Exception as e:
            print(f"[agent3] OpenRouter 오류: {e}", file=sys.stderr)
    if anthropic_key:
        payload = json.dumps({
            "model": model, "max_tokens": 400, "system": system_prompt,
            "messages": [{"role": "user", "content": user_content}]
        }).encode()
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages", data=payload,
            headers={"Content-Type": "application/json", "x-api-key": anthropic_key,
                     "anthropic-version": "2023-06-01"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read())["content"][0]["text"].strip()
        except urllib.error.HTTPError as e:
            print(f"[agent3] Anthropic 오류: HTTP {e.code}: {e.read().decode()[:150]}", file=sys.stderr)
        except Exception as e:
            print(f"[agent3] Anthropic 오류: {e}", file=sys.stderr)
    return "• 요약 생략 (API 키 없음)"

# ── 데이터 로드 ───────────────────────────────────────────────────────────────
def load(path):
    try:
        with open(path) as f: return json.load(f)
    except: return []

news   = load(news_path)
papers = load(papers_path)
print(f"[agent3] 뉴스 {len(news)}건, 논문 {len(papers)}건 점수 계산 중...", file=sys.stderr)

# ── 점수 계산 및 날짜 보강 ────────────────────────────────────────────────────
def enrich(item, body_key='summary'):
    body = item.get(body_key) or item.get('abstract', '') or ''
    text = f"{item['title']} {body}"
    return {**item, '_body': body,
            'category': categorize(text),
            'score':    min(keyword_score(text), 10),
            'date_kr':  date_to_kr(item.get('date', ''))}

scored_news   = [enrich(i, 'summary')  for i in news]
scored_papers = [enrich(i, 'abstract') for i in papers]

# ── 오늘(24h 윈도우) / 폴백 분류 ─────────────────────────────────────────────
today_news_raw   = sorted([i for i in scored_news   if in_window(i)], key=lambda x: x['score'], reverse=True)[:max_news]
today_papers_raw = sorted([i for i in scored_papers if in_window(i)], key=lambda x: x['score'], reverse=True)[:max_papers]

fallback_news_raw = sorted([i for i in scored_news if not in_window(i)], key=lambda x: x['score'], reverse=True)[:3]
# 폴백 논문: 날짜 최신순 1건
_fp = [i for i in scored_papers if not in_window(i)]
_fp.sort(key=lambda x: parse_date(x.get('date','')) or datetime(2000,1,1,tzinfo=timezone.utc), reverse=True)
fallback_papers_raw = _fp[:1]

# ── AI 요약: 오늘 항목 + 폴백 논문만 (폴백 뉴스는 제목만 사용) ────────────────
def summarize_list(items):
    out = []
    for item in items:
        body = item.pop('_body', '')
        item['summary'] = ai_summarize(item['title'], body)
        out.append(item)
    return out

def clean_list(items):
    for item in items: item.pop('_body', None); item.setdefault('summary', '')
    return items

n_api = len(today_news_raw) + len(today_papers_raw) + (0 if today_papers_raw else len(fallback_papers_raw))
print(f"[agent3] 요약 시작 — 뉴스 {len(today_news_raw)}건('오늘'), 논문 {len(today_papers_raw) or len(fallback_papers_raw)}건 (API {n_api}회)...", file=sys.stderr)

today_news_final      = summarize_list(today_news_raw)
fallback_news_final   = clean_list(fallback_news_raw)
today_papers_final    = summarize_list(today_papers_raw)
fallback_papers_final = summarize_list(fallback_papers_raw) if not today_papers_raw else []

# ── 출력 JSON ────────────────────────────────────────────────────────────────
result = {
    'report_date':      report_date,
    'report_date_kr':   report_date_kr,
    'window_start_kst': window_start.strftime('%Y-%m-%d'),
    'window_end_kst':   window_end.strftime('%Y-%m-%d'),
    'today_news':       today_news_final,
    'fallback_news':    fallback_news_final,
    'today_papers':     today_papers_final,
    'fallback_papers':  fallback_papers_final,
}
with open(output_path, 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

n = len(today_news_final) or len(fallback_news_final)
p = len(today_papers_final) or len(fallback_papers_final)
print(f"[agent3] 완료 — 뉴스 {n}건({'오늘' if today_news_final else '폴백'}), 논문 {p}건({'오늘' if today_papers_final else '폴백'}) → {output_path}", file=sys.stderr)
PYEOF

echo "[agent3] 요약 결과 저장 완료: $OUTPUT" >&2
cat "$OUTPUT"

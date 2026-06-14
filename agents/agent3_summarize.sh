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

# 인자 파싱
news_path, papers_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]
max_news      = int(sys.argv[4])
max_papers    = int(sys.argv[5])
or_key        = sys.argv[6]
anthropic_key = sys.argv[7]
model         = sys.argv[8]
dry_run       = sys.argv[9] == "1"

# ── 카테고리 분류 규칙 ─────────────────────────────────────────────────────────
# 각 카테고리를 나타내는 키워드 패턴 (우선순위 순)
CATEGORIES = {
    'SysML':    re.compile(r'SysML|UML', re.I),
    'UAF':      re.compile(r'UAF|DoDAF|UPDM|NATO', re.I),
    'Tool':     re.compile(r'Cameo|Capella|Rhapsody|MagicDraw|도구|software|tool', re.I),
    'Standard': re.compile(r'standard|ISO|IEEE|OMG|specification|표준', re.I),
    'Research': re.compile(r'survey|framework|ontology|formal|method|연구', re.I),
    'Industry': re.compile(r'industr|defense|aerospace|automotive|enterprise|산업', re.I),
}

def categorize(text: str) -> str:
    """텍스트에서 첫 번째로 매칭되는 카테고리를 반환한다."""
    for cat, pat in CATEGORIES.items():
        if pat.search(text):
            return cat
    return 'Research'  # 기본값

def keyword_score(text: str) -> int:
    """
    텍스트에서 MBSE 핵심 키워드 밀도를 정수 점수로 반환한다.
    핵심 키워드(MBSE, SysML, UAF): 3점, 관련 키워드: 1점
    """
    core    = re.compile(r'\bMBSE\b|\bSysML\b|\bUAF\b', re.I)
    related = re.compile(
        r'systems.engineering|model.based|digital.twin|INCOSE|Cameo|Capella', re.I)
    return len(core.findall(text)) * 3 + len(related.findall(text))

def ai_summarize(title: str, body: str) -> str:
    """
    AI API로 제목+내용을 3줄 한국어로 요약한다.
    우선순위: Groq (무료) → Anthropic → 더미
    skills.sh 의 ai_summarize() 와 동일한 로직을 Python 으로 구현한 버전.
    """
    if dry_run:
        return f"• [DRY-RUN] {title[:80]}\n• 요약 생략 (DRY_RUN 모드)"

    system_prompt = "MBSE 전문가로서 핵심만 3줄 한국어로 요약하세요. 각 줄은 •로 시작하세요."
    user_content  = f"제목: {title}\n\n내용: {body[:2000]}"

    # ── OpenRouter API (무료 모델) ──────────────────────────────────────────
    if or_key:
        payload = json.dumps({
            "model":    "google/gemma-4-31b-it:free",
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user",   "content": user_content}
            ],
            "max_tokens": 300
        }).encode()
        req = urllib.request.Request(
            "https://openrouter.ai/api/v1/chat/completions",
            data=payload,
            headers={"Content-Type": "application/json",
                     "Authorization": f"Bearer {or_key}"},
            method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                d = json.loads(resp.read())
                return d["choices"][0]["message"]["content"].strip()
        except urllib.error.HTTPError as e:
            err = e.read().decode('utf-8', errors='replace')
            print(f"[agent3] OpenRouter 오류: HTTP {e.code}: {err[:200]}", file=sys.stderr)
        except Exception as e:
            print(f"[agent3] OpenRouter 오류: {e}", file=sys.stderr)

    # ── Anthropic 폴백 ──────────────────────────────────────────────────────
    if anthropic_key:
        payload = json.dumps({
            "model":    model,
            "max_tokens": 300,
            "system":   system_prompt,
            "messages": [{"role": "user", "content": user_content}]
        }).encode()
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages",
            data=payload,
            headers={"Content-Type": "application/json",
                     "x-api-key": anthropic_key,
                     "anthropic-version": "2023-06-01"},
            method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                d = json.loads(resp.read())
                return d["content"][0]["text"].strip()
        except urllib.error.HTTPError as e:
            err = e.read().decode('utf-8', errors='replace')
            print(f"[agent3] Anthropic 오류: HTTP {e.code}: {err[:200]}", file=sys.stderr)
        except Exception as e:
            print(f"[agent3] Anthropic 오류: {e}", file=sys.stderr)

    return "• API 키 미설정 — 요약 생략"

def load(path):
    """JSON 파일 로드, 실패 시 빈 배열 반환"""
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return []

news   = load(news_path)
papers = load(papers_path)

results = {"news": [], "papers": []}
print(f"[agent3] 뉴스 {len(news)}건, 논문 {len(papers)}건 요약 시작...", file=sys.stderr)

# ── 뉴스 처리 ──────────────────────────────────────────────────────────────────
for item in news:
    body  = item.get('summary', '') or item.get('abstract', '')
    text  = f"{item['title']} {body}"
    score = min(keyword_score(text), 10)   # 최대 10점으로 제한

    summary = ai_summarize(item['title'], body)

    results["news"].append({
        **item,
        "summary":  summary,
        "category": categorize(text),
        "score":    score,
    })

# ── 논문 처리 ──────────────────────────────────────────────────────────────────
for item in papers:
    body  = item.get('abstract', '')
    text  = f"{item['title']} {body}"
    score = min(keyword_score(text), 10)

    summary = ai_summarize(item['title'], body)

    results["papers"].append({
        **item,
        "summary":  summary,
        "category": categorize(text),
        "score":    score,
    })

# ── 정렬 및 상위 N건 유지 ─────────────────────────────────────────────────────
# 점수 내림차순으로 정렬 후 상위 MAX_NEWS / MAX_PAPERS 건만 유지
results["news"]   = sorted(results["news"],   key=lambda x: x["score"], reverse=True)[:max_news]
results["papers"] = sorted(results["papers"], key=lambda x: x["score"], reverse=True)[:max_papers]

with open(output_path, "w") as f:
    json.dump(results, f, ensure_ascii=False, indent=2)

n = len(results["news"])
p = len(results["papers"])
print(f"[agent3] 완료 — 뉴스 상위 {n}건, 논문 상위 {p}건 → {output_path}", file=sys.stderr)
PYEOF

echo "[agent3] 요약 결과 저장 완료: $OUTPUT" >&2
cat "$OUTPUT"

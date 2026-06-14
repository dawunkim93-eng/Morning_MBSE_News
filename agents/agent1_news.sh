#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 파일    : agents/agent1_news.sh
# 설명    : 뉴스 수집 에이전트.
#           Google News RSS 2개 피드와 INCOSE 홈페이지에서 MBSE 관련 뉴스를
#           수집하고, 키워드 필터링 및 캐시 중복 제거 후 JSON으로 출력한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — Google News RSS + INCOSE 뉴스 수집 구현
# ─────────────────────────────────────────────────────────────────────────────
#
# 출력:
#   stdout : JSON 배열 → /tmp/news_results.json
#   stderr : 진행 상황 로그
#
# 실행 조건:
#   skills.sh 에서 공유 함수를 로드해야 한다

set -euo pipefail

# 프로젝트 루트 디렉터리 (agents/ 의 상위 폴더)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 공유 유틸리티 함수 로드
source "$SCRIPT_DIR/skills.sh"

# ── 설정 ────────────────────────────────────────────────────────────────────
OUTPUT="$SHARED_TMP/news_results.json" # Phase 2 에이전트가 읽을 결과 파일
TSV_TMP=$(mktemp)                      # 필터링 작업용 임시 TSV 파일

# 뉴스를 수집할 Google News RSS 피드 URL 목록
RSS_SOURCES=(
    "https://news.google.com/rss/search?q=MBSE+systems+engineering&hl=en&gl=US&ceid=US:en"
    "https://news.google.com/rss/search?q=SysML+digital+engineering&hl=en&gl=US&ceid=US:en"
)

echo "[agent1] 뉴스 소스 수집 시작..." >&2

# ── Step 1: Google News RSS 피드 수집 ────────────────────────────────────────
# 각 RSS 피드를 순서대로 fetch하고 결과를 임시 TSV에 추가
for src in "${RSS_SOURCES[@]}"; do
    echo "[agent1] RSS 수집: $src" >&2
    fetch_rss "$src" >> "$TSV_TMP" 2>/dev/null || \
        echo "[agent1] 경고: $src 수집 실패" >&2
done

# ── Step 2: INCOSE 뉴스 페이지 수집 ──────────────────────────────────────────
echo "[agent1] INCOSE 홈페이지 수집..." >&2
incose_html=$(web_fetch "https://www.incose.org/news-and-events/news") || incose_html=""

if [[ -n "$incose_html" ]]; then
    # ※ pipe+heredoc 충돌 방지: HTML을 임시 파일로 전달 (sys.argv[1])
    # local 은 함수 안에서만 유효 — 메인 스크립트 바디에서는 직접 대입
    _html_tmp=$(mktemp)
    printf '%s' "$incose_html" > "$_html_tmp"
    python3 - "$_html_tmp" "$SCRIPT_DIR/cache/seen_urls.txt" <<'PYEOF' >> "$TSV_TMP"
import sys, re
html_file  = sys.argv[1] if len(sys.argv) > 1 else ""
cache_file = sys.argv[2] if len(sys.argv) > 2 else ""
with open(html_file, encoding='utf-8', errors='replace') as f:
    html = f.read()

# 기존 캐시 URL 로드 (중복 수집 방지)
cached = set()
try:
    with open(cache_file) as f:
        cached = set(f.read().splitlines())
except:
    pass

seen = set()
# href + 텍스트 링크 패턴 추출
pattern = r'<a[^>]+href=["\']([^"\']+)["\'][^>]*>\s*([^<]{20,})\s*</a>'
for href, text in re.findall(pattern, html, re.DOTALL):
    text = re.sub(r'\s+', ' ', text).strip()
    if not href.startswith('http'):
        href = 'https://www.incose.org' + href
    if href in seen or href in cached:
        continue
    # MBSE 관련 텍스트만 포함
    if re.search(r'MBSE|SysML|systems.engineering|INCOSE|model.based', text, re.I):
        seen.add(href)
        print(f"{text}|{href}|")
PYEOF
    rm -f "$_html_tmp"
fi

# ── Step 3: 키워드 필터링 ─────────────────────────────────────────────────────
# MBSE 관련 키워드가 포함된 항목만 유지
filtered=$(filter_keywords "$TSV_TMP" \
    MBSE SysML UAF "digital.twin" "systems.engineering" \
    Cameo model-based INCOSE DoDAF UPDM Capella)

# ── Step 4: 캐시 기반 중복 제거 ───────────────────────────────────────────────
# 이미 발송된 URL은 제거
echo "$filtered" > "$TSV_TMP"
deduplicate "$TSV_TMP"

# ── Step 5: JSON 배열 생성 ────────────────────────────────────────────────────
# TSV를 JSON 배열로 변환해 출력 파일에 저장
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
        # Google News 제목 끝 " - 언론사명" 제거
        title = re.sub(r'\s+-\s+[^-]{3,40}$', '', title).strip()
        if title and url:
            items.append({
                'title':   title,
                'url':     url,
                'date':    date,
                'source':  'news',
                'summary': ''
            })

print(json.dumps(items, ensure_ascii=False, indent=2))
PYEOF

# 수집 결과 집계 및 stdout 출력
count=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(len(d))")
echo "[agent1] 완료 — 신규 뉴스 ${count}건 → $OUTPUT" >&2
cat "$OUTPUT"   # stdout 으로 출력 (orchestrator 가 캡처)

# 임시 파일 정리
rm -f "$TSV_TMP"

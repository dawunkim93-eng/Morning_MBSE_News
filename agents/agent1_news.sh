#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 파일    : agents/agent1_news.sh
# 설명    : 뉴스 수집 에이전트.
#           Google News RSS (키워드 쿼리 + site: 쿼리)와 OMG 보도자료 페이지에서
#           MBSE 관련 뉴스를 수집하고, 키워드 필터링 및 캐시 중복 제거 후
#           JSON으로 출력한다.
#
#           소스 구성:
#             1. Google News RSS 키워드 쿼리 — keyword_loader 플러그인 상위 8개
#             2. Google News RSS site:incose.org — INCOSE 공식 뉴스
#               (incose.org 는 Cloudflare 차단으로 직접 스크래핑 불가 → Google 우회)
#             3. Google News RSS site:omg.org — OMG 관련 뉴스
#             4. OMG pressroom 직접 파싱 — 공식 보도자료 (source: omg_press)
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — Google News RSS + INCOSE 뉴스 수집 구현
#   v1.1   2026-09-26   개정 — RSS 쿼리를 keyword_loader 플러그인에서 동적 생성(--limit 8),
#                        site:incose.org / site:omg.org 쿼리 추가,
#                        OMG pressroom 직접 파싱 추가(source: omg_press),
#                        INCOSE 직접 스크래핑 제거(Cloudflare 차단),
#                        필터 인자 하드코딩 제거(플러그인 filter 자동 로드)
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
MAX_RSS_QUERIES=8                      # 키워드 RSS 쿼리 상한 (플러그인 순서대로)

# ── Step 0: 플러그인에서 RSS 쿼리 동적 생성 ─────────────────────────────────
# keywords/*.yml 의 google_news 쿼리를 priority 순 + 파일 내 순서대로 상위 N개 로드
declare -a RSS_QUERIES=()
while IFS= read -r q; do
    [[ -n "$q" ]] && RSS_QUERIES+=("$q")
done < <(python3 "$SCRIPT_DIR/keyword_loader.py" --format google --limit "$MAX_RSS_QUERIES")

if [[ ${#RSS_QUERIES[@]} -eq 0 ]]; then
    # 플러그인 로드 실패 시 최소 폴백
    RSS_QUERIES=("MBSE systems engineering" "Model-Based Systems Engineering")
    echo "[agent1] 경고: 플러그인 쿼리 로드 실패 — 폴백 쿼리 사용" >&2
fi

# ── RSS 소스 구성 ─────────────────────────────────────────────────────────────
# 메인: Bing News RSS — 원문 URL을 직접 제공 (Google News 인코딩 링크 문제 해결)
# 보조: Google News RSS site: 쿼리 — INCOSE/OMG 사이트 뉴스 우회 수집
#       (단, exclude_non_news 필터로 스펙문서·메뉴 페이지 제거)
RSS_SOURCES=()
for q in "${RSS_QUERIES[@]}"; do
    enc=$(urlencode "$q")
    RSS_SOURCES+=("https://www.bing.com/news/search?q=${enc}&format=rss")
done
GOOGLE_SITE_SOURCES=(
    "https://news.google.com/rss/search?q=site%3Aincose.org&hl=en&gl=US&ceid=US:en"
    "https://news.google.com/rss/search?q=site%3Aomg.org&hl=en&gl=US&ceid=US:en"
)

echo "[agent1] 뉴스 소스 수집 시작 — Bing ${#RSS_SOURCES[@]}피드 + Google site: ${#GOOGLE_SITE_SOURCES[@]} + OMG 직접" >&2

# ── Step 1: Bing News RSS 수집 (원문 직결 링크) ──────────────────────────────
for src in "${RSS_SOURCES[@]}"; do
    echo "[agent1] Bing RSS 수집: $src" >&2
    fetch_rss "$src" >> "$TSV_TMP" 2>/dev/null || \
        echo "[agent1] 경고: $src 수집 실패" >&2
done

# Bing 리디렉션 URL의 url= 파라미터에서 원문 URL 추출
# (bing.com/news/apiclick.aspx?...&url=<원문인코딩> 형태)
bing_decode_tsv() {
    local src_file="$1"
    python3 - "$src_file" <<'PYEOF'
import sys, re, urllib.parse
with open(sys.argv[1]) as f:
    for line in f:
        line = line.rstrip('\n')
        if not line:
            continue
        parts = line.split('|')
        title = parts[0] if len(parts) > 0 else ''
        link = parts[1] if len(parts) > 1 else ''
        date = parts[2] if len(parts) > 2 else ''
        # bing.com/news/apiclick.aspx?...&url=<원문> 파라미터 추출
        m = re.search(r'[?&]url=([^&]+)', link)
        if m:
            orig = urllib.parse.unquote(m.group(1))
            if orig.startswith('http'):
                print(f"{title}|{orig}|{date}")
                continue
        # url= 파라미터가 없으면 원본 링크 유지 (이미 직접 URL인 경우)
        if link.startswith('http') and 'bing.com' not in link:
            print(f"{title}|{link}|{date}")
PYEOF
}

BING_RAW=$(mktemp)
cp "$TSV_TMP" "$BING_RAW"
: > "$TSV_TMP"
bing_decode_tsv "$BING_RAW" >> "$TSV_TMP" || true
rm -f "$BING_RAW"

bing_count=$(wc -l < "$TSV_TMP" | tr -d ' ')
echo "[agent1] Bing 원문 링크 ${bing_count}건 변환 완료" >&2

# ── Step 2: Google News site: 쿼리 수집 (INCOSE/OMG 보조 소스) ────────────────
# 신형 인코딩 링크는 브라우저 JS 리디렉션 의존이지만, INCOSE/OMG 공식 소식은
# 이 경로로만 수집 가능하므로 보조 소스로 유지. 가짜 뉴스 필터로 노이즈 제거.
for src in "${GOOGLE_SITE_SOURCES[@]}"; do
    echo "[agent1] Google site: RSS 수집: $src" >&2
    fetch_rss "$src" >> "$TSV_TMP" 2>/dev/null || \
        echo "[agent1] 경고: $src 수집 실패" >&2
done

# ── Step 2: OMG 보도자료 수집 (pressroom 직접 파싱) ─────────────────────────
# omg.org 는 Cloudflare 차단 없이 직접 스크래핑 가능.
# 보도자료 URL 패턴: releases/prYYYY/MM-DD-YY.htm → 날짜를 URL에서 파싱.
echo "[agent1] OMG pressroom 수집..." >&2
omg_html=$(web_fetch "https://www.omg.org/news/pressroom.htm") || omg_html=""

if [[ -n "$omg_html" ]]; then
    # ※ pipe+heredoc 충돌 방지: HTML을 임시 파일로 전달 (sys.argv[1])
    _html_tmp=$(mktemp)
    printf '%s' "$omg_html" > "$_html_tmp"
    python3 - "$_html_tmp" >> "$TSV_TMP" <<'PYEOF'
import sys, re
with open(sys.argv[1], encoding='utf-8', errors='replace') as f:
    html = f.read()

# 보도자료 링크 패턴: releases/prYYYY/MM-DD-YY.htm
pattern = r'<a[^>]+href="([^"]*releases/pr(\d{4})/(\d{2})-(\d{2})-(\d{2})\.htm)"[^>]*>(.*?)</a>'
seen = set()
for href, year, month, day, yy, text in re.findall(pattern, html, re.DOTALL):
    text = re.sub(r'<[^>]+>', '', text)
    text = re.sub(r'\s+', ' ', text).strip()
    if not href.startswith('http'):
        href = 'https://www.omg.org/' + href.lstrip('/')
    if href in seen:
        continue
    # URL 날짜 파싱: pr2025/07-21-25.htm → 2025-07-21
    date = f"{year}-{month}-{day}"
    seen.add(href)
    print(f"{text}|{href}|{date}")
PYEOF
    rm -f "$_html_tmp"
else
    echo "[agent1] 경고: OMG pressroom 수집 실패" >&2
fi

# ── Step 3: 가짜 뉴스 제외 필터 ───────────────────────────────────────────────
# site: 쿼리가 수집한 스펙문서·메뉴·챕터 페이지 제거 (skills.sh 의 exclude_non_news)
filtered=$(exclude_non_news "$TSV_TMP")

# ── Step 4: 키워드 필터링 ─────────────────────────────────────────────────────
# 키워드 인자 없이 호출 → skills.sh 의 filter_keywords() 가
# keyword_loader.py 를 통해 플러그인 filter 패턴을 자동 로드한다.
# ※ Bing 원문 링크와 OMG 보도자료는 URL 자체가 유효하므로 유지
filtered=$(echo "$filtered" | filter_keywords -)

# ── Step 5: 캐시 기반 중복 제거 ───────────────────────────────────────────────
# 이미 처리된 URL은 제거
echo "$filtered" > "$TSV_TMP"
deduplicate "$TSV_TMP"

# ── Step 6: JSON 배열 생성 ────────────────────────────────────────────────────
# TSV를 JSON 배열로 변환해 출력 파일에 저장
# source 판별: omg.org 링크이면서 보도자료 패턴이면 omg_press, 그 외 news
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
            source = ('omg_press' if re.search(r'omg\.org/(news/)?releases/pr\d{4}', url)
                      else 'news')
            items.append({
                'title':   title,
                'url':     url,
                'date':    date,
                'source':  source,
                'summary': ''
            })

print(json.dumps(items, ensure_ascii=False, indent=2))
PYEOF

# 수집 결과 집계 및 stdout 출력
count=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(len(d))")
omg_count=$(python3 -c "import json; d=json.load(open('$OUTPUT')); print(sum(1 for i in d if i['source']=='omg_press'))")
echo "[agent1] 완료 — 신규 뉴스 ${count}건 (OMG 보도자료 ${omg_count}건 포함) → $OUTPUT" >&2
cat "$OUTPUT"   # stdout 으로 출력 (orchestrator 가 캡처)

# 임시 파일 정리
rm -f "$TSV_TMP"
#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 파일    : agents/agent2_papers.sh
# 설명    : 논문 수집 에이전트.
#           arXiv API와 Semantic Scholar API를 동시(병렬)에 요청해 MBSE 관련
#           최신 논문을 수집한다. 인용 수 2 미만의 논문은 노이즈로 간주해 제거한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — arXiv + Semantic Scholar 병렬 수집 구현
# ─────────────────────────────────────────────────────────────────────────────
#
# 출력:
#   stdout : JSON 배열 → /tmp/papers_results.json
#   stderr : 진행 상황 로그

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/skills.sh"

# ── 설정 ────────────────────────────────────────────────────────────────────
OUTPUT="$SHARED_TMP/papers_results.json" # Phase 2 에이전트가 읽을 결과 파일
ARXIV_TMP=$(mktemp)                    # arXiv 결과 임시 파일
SEMANTIC_TMP=$(mktemp)                 # Semantic Scholar 결과 임시 파일

echo "[agent2] 논문 소스 병렬 수집 시작..." >&2

# ── Step 0: 플러그인에서 쿼리 동적 생성 ─────────────────────────────────────
# keywords/*.yml 의 arxiv / semantic_scholar 쿼리를 keyword_loader 로 로드
ARXIV_QUERY_RAW=$(python3 "$SCRIPT_DIR/keyword_loader.py" --format arxiv)
SEMANTIC_QUERY=$(python3 "$SCRIPT_DIR/keyword_loader.py" --format semantic)

# arXiv 쿼리 문자열 조립: 각 쿼리를 ti:/abs: 필드 검색으로 변환 후 OR 결합
#   예) "Model-Based Systems Engineering" → ti:"..." OR abs:"..."
#   복수 단어 쿼리는 반드시 따옴표로 감싸야 arXiv API에서 구문으로 인식됨
ARXIV_QUERY=$(python3 - "$ARXIV_QUERY_RAW" <<'PYEOF'
import sys, urllib.parse
queries = [q.strip() for q in sys.argv[1].splitlines() if q.strip()]
parts = []
for q in queries:
    enc = urllib.parse.quote_plus(f'"{q}"')   # 구문 검색용 따옴표 포함 인코딩
    parts.append(f'ti:{enc}')
    parts.append(f'abs:{enc}')
print('+OR+'.join(parts) if parts else 'all:MBSE')
PYEOF
)

echo "[agent2] arXiv 쿼리 생성 완료 (${ARXIV_QUERY:0:80}...)" >&2
echo "[agent2] Semantic Scholar 쿼리: $SEMANTIC_QUERY" >&2

# ── Step 1: arXiv + Semantic Scholar 병렬 수집 ────────────────────────────────
# bash 백그라운드(&)로 두 소스를 동시에 요청해 총 대기 시간을 단축

(
    # arXiv: curl 대신 Python urllib 사용 (GitHub Actions에서 더 안정적)
    echo "[agent2] arXiv 요청 (Python urllib)..." >&2
    python3 - "$ARXIV_TMP" "$ARXIV_QUERY" <<'PYEOF'
import sys, json, urllib.request, xml.etree.ElementTree as ET

# 쿼리 문자열은 스크립트 인자로 전달받음 (keyword_loader 플러그인에서 생성, 이미 인코딩됨)
query = sys.argv[2]
arxiv_url = (
    "https://export.arxiv.org/api/query"
    f"?search_query={query}"
    "&sortBy=submittedDate&sortOrder=descending&max_results=20"
)
ns = {'atom': 'http://www.w3.org/2005/Atom'}
out_path = sys.argv[1]
try:
    req = urllib.request.Request(
        arxiv_url,
        headers={'User-Agent': 'MBSE-News-Bot/1.0 (daily briefing; contact via GitHub)'}
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        content = r.read().decode('utf-8')
    root  = ET.fromstring(content)
    items = []
    for entry in root.findall('atom:entry', ns):
        t = entry.find('atom:title',     ns)
        l = entry.find('atom:id',        ns)
        p = entry.find('atom:published', ns)
        s = entry.find('atom:summary',   ns)
        title    = t.text.strip().replace('\n', ' ') if t is not None else ''
        url      = l.text.strip()              if l is not None else ''
        date     = p.text[:10]                 if p is not None else ''
        abstract = s.text.strip().replace('\n', ' ') if s is not None else ''
        authors  = ', '.join(
            a.find('atom:name', ns).text.strip()
            for a in entry.findall('atom:author', ns)
            if a.find('atom:name', ns) is not None
        )
        if title and url:
            items.append({'title': title, 'url': url, 'date': date,
                          'abstract': abstract, 'authors': authors,
                          'source': 'arxiv', 'citation_count': 99})
    with open(out_path, 'w') as f:
        json.dump(items, f, ensure_ascii=False)
    print(f'[agent2-arxiv] {len(items)}건 수집', file=sys.stderr)
except Exception as e:
    print(f'[agent2-arxiv] 오류: {e}', file=sys.stderr)
    with open(out_path, 'w') as f:
        f.write('[]')
PYEOF
) &
PID_ARXIV=$!  # arXiv 백그라운드 프로세스 PID

(
    # Semantic Scholar: MBSE 관련 논문 검색 (인용 정보 포함)
    # 쿼리는 keyword_loader 플러그인(semantic_scholar 항목)에서 생성
    enc_query=$(urlencode "$SEMANTIC_QUERY")
    sem_url="https://api.semanticscholar.org/graph/v1/paper/search?query=${enc_query}&fields=title,abstract,authors,year,citationCount,externalIds&limit=10"
    echo "[agent2] Semantic Scholar 요청: $sem_url" >&2
    json=$(web_fetch "$sem_url") || exit 0

    # ※ pipe+heredoc 충돌 방지: JSON을 임시 파일로 전달
    # 서브쉘(...)에서는 local 사용 불가 — 직접 대입
    _json_tmp=$(mktemp)
    printf '%s' "$json" > "$_json_tmp"
    python3 - "$_json_tmp" <<'PYEOF' > "$SEMANTIC_TMP"
import sys, json
try:
    with open(sys.argv[1]) as f:
        d = json.loads(f.read())
    items = []
    for p in d.get('data', []):
        title    = p.get('title', '')
        year     = str(p.get('year', '')) if p.get('year') else ''
        abstract = (p.get('abstract') or '').replace('\n', ' ')
        cites    = p.get('citationCount', 0) or 0
        ext_ids  = p.get('externalIds', {}) or {}
        doi      = ext_ids.get('DOI', '')
        # DOI가 있으면 doi.org URL, 없으면 Semantic Scholar 페이지 URL
        url = (f"https://doi.org/{doi}" if doi
               else f"https://www.semanticscholar.org/paper/{p.get('paperId','')}")
        if title:
            items.append({'title': title, 'url': url, 'date': year,
                          'abstract': abstract, 'source': 'semantic',
                          'citation_count': cites})
    print(json.dumps(items, ensure_ascii=False))
except Exception as e:
    print(f'[agent2-semantic] 오류: {e}', file=sys.stderr)
    print('[]')
PYEOF
    rm -f "$_json_tmp"
) &
PID_SEMANTIC=$!  # Semantic Scholar 백그라운드 프로세스 PID

# 두 백그라운드 작업이 모두 완료될 때까지 대기
wait $PID_ARXIV $PID_SEMANTIC
echo "[agent2] 두 소스 수집 완료" >&2

# ── Step 2: 병합 + 필터링 + 중복 제거 ────────────────────────────────────────
# MBSE 관련 키워드 패턴은 keyword_loader 플러그인(filter 항목)에서 로드
FILTER_PATTERN=$(python3 "$SCRIPT_DIR/keyword_loader.py" --format filter --separator '|')

python3 - "$ARXIV_TMP" "$SEMANTIC_TMP" "$SCRIPT_DIR/cache/seen_urls.txt" "$FILTER_PATTERN" <<'PYEOF' > "$OUTPUT"
import sys, json, re

def load_json(path):
    """JSON 파일 로드, 실패 시 빈 배열 반환"""
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return []

def load_cache(path):
    """URL 캐시 파일 로드, 없으면 빈 집합 반환"""
    try:
        with open(path) as f:
            return set(f.read().splitlines())
    except:
        return set()

# MBSE 관련 키워드 패턴 (제목 + 초록 검색용) — 플러그인 filter에서 생성
# grep -E 호환 패턴이므로 그대로 정규식으로 사용
KEYWORDS = re.compile(sys.argv[4], re.I)

cache      = load_cache(sys.argv[3])
all_items  = load_json(sys.argv[1]) + load_json(sys.argv[2])  # arXiv + Semantic Scholar 병합

seen_urls   = set()
seen_titles = set()
results     = []

for item in all_items:
    title    = item.get('title', '')
    url      = item.get('url',   '')
    abstract = item.get('abstract', '')
    cites    = item.get('citation_count', 0) or 0

    # Semantic Scholar 노이즈 필터: 인용 수 2 미만 제거 (arXiv는 항상 통과)
    if item.get('source') == 'semantic' and cites < 2:
        continue

    # 키워드 관련성 필터 (arXiv는 검색쿼리에서 이미 필터됨 — 건너뜀)
    if item.get('source') != 'arxiv' and not KEYWORDS.search(title + ' ' + abstract):
        continue

    # URL/제목 중복 및 캐시 확인
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
echo "[agent2] 완료 — 신규 논문 ${count}건 → $OUTPUT" >&2
cat "$OUTPUT"

# 임시 파일 정리
rm -f "$ARXIV_TMP" "$SEMANTIC_TMP"

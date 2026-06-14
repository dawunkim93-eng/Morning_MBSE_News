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

# ── Step 1: arXiv + Semantic Scholar 병렬 수집 ────────────────────────────────
# bash 백그라운드(&)로 두 소스를 동시에 요청해 총 대기 시간을 단축

(
    # arXiv: MBSE OR SysML OR "systems engineering" 최신 논문 15편
    arxiv_url="https://export.arxiv.org/api/query?search_query=all:MBSE+OR+all:SysML+OR+all:%22systems+engineering%22&sortBy=submittedDate&sortOrder=descending&max_results=15"
    echo "[agent2] arXiv 요청: $arxiv_url" >&2
    xml=$(web_fetch "$arxiv_url") || exit 0

    # ※ pipe+heredoc 충돌 방지: XML을 임시 파일로 전달
    # 서브쉘(...)에서는 local 사용 불가 — 직접 대입
    _xml_tmp=$(mktemp)
    printf '%s' "$xml" > "$_xml_tmp"
    python3 - "$_xml_tmp" <<'PYEOF' > "$ARXIV_TMP"
import sys, json, xml.etree.ElementTree as ET
ns = {'atom': 'http://www.w3.org/2005/Atom'}
try:
    with open(sys.argv[1]) as f:
        content = f.read()
    root  = ET.fromstring(content)
    items = []
    for entry in root.findall('atom:entry', ns):
        t = entry.find('atom:title',     ns)
        l = entry.find('atom:id',        ns)  # arXiv에서는 id 가 URL
        p = entry.find('atom:published', ns)
        s = entry.find('atom:summary',   ns)  # 논문 초록
        title    = t.text.strip().replace('\n', ' ') if t is not None else ''
        url      = l.text.strip()              if l is not None else ''
        date     = p.text[:10]                 if p is not None else ''
        abstract = s.text.strip().replace('\n', ' ') if s is not None else ''
        if title and url:
            # arXiv 논문은 항상 포함(citation_count=99 로 필터 통과)
            items.append({'title': title, 'url': url, 'date': date,
                          'abstract': abstract, 'source': 'arxiv', 'citation_count': 99})
    print(json.dumps(items, ensure_ascii=False))
except Exception as e:
    print(f'[agent2-arxiv] 오류: {e}', file=sys.stderr)
    print('[]')  # 실패 시 빈 배열 반환
PYEOF
    rm -f "$_xml_tmp"
) &
PID_ARXIV=$!  # arXiv 백그라운드 프로세스 PID

(
    # Semantic Scholar: MBSE 관련 논문 검색 (인용 정보 포함)
    sem_url="https://api.semanticscholar.org/graph/v1/paper/search?query=model-based+systems+engineering&fields=title,abstract,authors,year,citationCount,externalIds&limit=10"
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
python3 - "$ARXIV_TMP" "$SEMANTIC_TMP" "$SCRIPT_DIR/cache/seen_urls.txt" <<'PYEOF' > "$OUTPUT"
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

# MBSE 관련 키워드 패턴 (제목 + 초록 검색용)
KEYWORDS = re.compile(
    r'MBSE|SysML|UAF|digital.twin|systems.engineering|'
    r'Cameo|model.based|INCOSE|DoDAF|UPDM|Capella', re.I)

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

    # 키워드 관련성 필터
    if not KEYWORDS.search(title + ' ' + abstract):
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

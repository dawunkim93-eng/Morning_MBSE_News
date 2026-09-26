#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 파일    : skills.sh
# 설명    : 모든 bash 에이전트가 source 해서 사용하는 공유 유틸리티 함수 모음.
#           네트워크 요청, HTML/RSS 파싱, 캐시 관리, AI 요약 등
#           공통 기능을 제공한다.
#           키워드는 load_keywords() 를 통해 keywords/*.yml 플러그인에서 로드한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — 네트워크·필터링·AI·텔레그램 공유 함수 구현
#   v1.1   2026-06-10   load_keywords() 추가, filter_keywords() 플러그인 연동
#   v1.2   2026-09-26   정리 — 텔레그램 전송·MarkdownV2·urlencode 함수 제거
#                       (텔레그램 발송 중지, agent4는 python 인라인 사용)
# ─────────────────────────────────────────────────────────────────────────────
#
# 사용법:
#   source skills.sh   (각 에이전트 스크립트 상단에서 호출)
#
# 전제 조건:
#   - curl, python3 가 PATH에 있어야 한다
#   - .env 파일에 ANTHROPIC_API_KEY 가 설정되어 있어야 한다

set -euo pipefail  # 오류 발생 시 즉시 종료, 미정의 변수 오류 처리

# ── 프로젝트 루트 경로 설정 ────────────────────────────────────────────────────
# 이미 SCRIPT_DIR이 설정된 경우(에이전트에서 설정) 덮어쓰지 않음
: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# ── 환경변수 로드 (.env 파일) ─────────────────────────────────────────────────
# set -a/+a 로 감싸면 .env의 변수가 자동으로 export 됨
[[ -f "$SCRIPT_DIR/.env" ]] && set -a && source "$SCRIPT_DIR/.env" && set +a

# ── Windows 호환: python3 명령어가 없으면 python 으로 대체 ────────────────────
if ! command -v python3 &>/dev/null || ! python3 --version &>/dev/null 2>&1; then
    python3() { python "$@"; }
    export -f python3
fi

# ── Python과 공유 가능한 임시 디렉터리 (Windows /tmp/ 경로 불일치 방지) ──────
# Bash의 /tmp/ 는 MSYS2 경로이지만 Windows Python은 이를 인식하지 못한다.
# Python의 tempfile.gettempdir()로 양쪽이 모두 접근 가능한 경로를 구한다.
SHARED_TMP="$(python3 -c 'import tempfile, pathlib; print(pathlib.Path(tempfile.gettempdir()).as_posix())')"
export SHARED_TMP

# ═════════════════════════════════════════════════════════════════════════════
# 네트워크 함수
# ═════════════════════════════════════════════════════════════════════════════

web_fetch() {
    # 인자: <url>
    # 설명: curl 로 URL을 요청하고 본문을 출력한다.
    #       최대 3회 재시도, 실패 시 오류 메시지를 stderr 로 출력하고 return 1.
    local url="$1"
    local attempt delay=2

    for attempt in 1 2 3; do
        local out
        if out=$(curl -s -L --max-time 30 --retry 0 \
                    -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
                    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
                    "$url" 2>/dev/null); then
            echo "$out"
            return 0
        fi
        echo "[web_fetch] 시도 $attempt 실패: $url — ${delay}s 후 재시도" >&2
        sleep "$delay"
        delay=$((delay * 2))  # 지수 백오프: 2s → 4s → 8s
    done

    echo "[web_fetch] 오류: 모든 재시도 실패 — $url" >&2
    return 1
}

fetch_rss() {
    # 인자: <url>
    # 설명: RSS/Atom XML을 가져와 "제목|URL|날짜" 형식의 TSV로 출력한다.
    #       RSS 2.0 형식(<item> 태그)을 파싱한다.
    #
    # ※ "echo $xml | python3 - <<'PYEOF'" 패턴은 파이프와 heredoc이 stdin을
    #   동시에 차지해 충돌한다. heredoc이 stdin을 가져가므로 파이프 데이터가
    #   유실된다. → XML을 임시 파일에 써서 인수로 전달하는 방식으로 수정.
    local url="$1"
    local xml _tmp

    xml=$(web_fetch "$url") || return 1
    _tmp=$(mktemp)
    printf '%s' "$xml" > "$_tmp"

    # 임시 파일 경로를 인수(sys.argv[1])로 전달 — stdin 충돌 없음
    python3 - "$_tmp" <<'PYEOF'
import sys, xml.etree.ElementTree as ET, re
try:
    with open(sys.argv[1]) as f:
        content = f.read()
    root = ET.fromstring(content)
    dc_ns = {'dc': 'http://purl.org/dc/elements/1.1/'}
    for item in root.findall('.//item'):
        t = item.find('title')
        l = item.find('link')
        # ※ Element 객체의 truth value 테스트 금지(deprecation) — is not None 사용
        d = item.find('pubDate')
        if d is None:
            d = item.find('dc:date', dc_ns)
        title = re.sub(r'<[^>]+>', '', (t.text or '')).strip().replace('|', '-') if t is not None else ''
        link  = (l.text or '').strip() if l is not None else ''
        date  = (d.text or '').strip() if d is not None else ''
        if title and link:
            print(f"{title}|{link}|{date}")
except Exception as e:
    print(f"[fetch_rss] 파싱 오류: {e}", file=sys.stderr)
PYEOF
    rm -f "$_tmp"
}

parse_html() {
    # 인자: <css_selector>
    # 설명: stdin 으로 받은 HTML에서 CSS selector에 매칭되는 텍스트를 추출한다.
    #       tag, .class, #id 형태의 단순 selector만 지원한다.
    local selector="$1"
    python3 - "$selector" <<'PYEOF'
import sys, re
selector = sys.argv[1]
html = sys.stdin.read()

# 단순 CSS selector 파싱: 태그명, .클래스, #아이디 분리
tag_m   = re.match(r'^([a-zA-Z]+)', selector)
class_m = re.search(r'\.([\w-]+)', selector)
id_m    = re.search(r'#([\w-]+)', selector)
tag = tag_m.group(1) if tag_m else r'\w+'

# 속성 매칭 패턴 생성
if class_m:
    attr = f'class=["\'][^"\']*{re.escape(class_m.group(1))}[^"\']*["\']'
elif id_m:
    attr = f'id=["\'][^"\']*{re.escape(id_m.group(1))}[^"\']*["\']'
else:
    attr = None

pattern = (rf'<{tag}[^>]*{attr}[^>]*>(.*?)</{tag}>' if attr
           else rf'<{tag}[^>]*>(.*?)</{tag}>')

for m in re.findall(pattern, html, re.DOTALL | re.IGNORECASE):
    clean = re.sub(r'<[^>]+>', '', m).strip()
    if clean:
        print(clean)
PYEOF
}

# ═════════════════════════════════════════════════════════════════════════════
# 키워드 플러그인 함수
# ═════════════════════════════════════════════════════════════════════════════

load_keywords() {
    # 인자: <format>  (naver|google|arxiv|semantic|filter|all)
    # 설명: keyword_loader.py 를 통해 keywords/*.yml 플러그인에서 키워드를 로드한다.
    #       형식별로 줄바꿈 구분 목록 또는 JSON 을 출력한다.
    #       keyword_loader.py 실행 실패 시 빈 문자열 반환 (에이전트가 기본값으로 폴백).
    local format="${1:-all}"
    python3 "$SCRIPT_DIR/keyword_loader.py" --format "$format" 2>/dev/null || true
}

# ═════════════════════════════════════════════════════════════════════════════
# 필터링 함수
# ═════════════════════════════════════════════════════════════════════════════

filter_keywords() {
    # 인자: <파일경로 또는 -> [키워드 ...]
    # 설명: 파일(또는 stdin)에서 MBSE 관련 키워드가 포함된 행만 출력한다.
    #       키워드 인자가 없으면 keywords/*.yml 플러그인에서 자동으로 로드한다.
    #       grep -i 로 대소문자 무관하게 필터링한다.
    local src="$1"; shift
    local pattern

    if [[ $# -eq 0 ]]; then
        # 인자 없음 → keyword_loader.py 에서 동적으로 로드
        local loaded
        loaded=$(python3 "$SCRIPT_DIR/keyword_loader.py" \
                    --format filter --separator '|' 2>/dev/null) || \
            loaded="MBSE|SysML|UAF|systems.engineering|model-based|INCOSE|Cameo|Capella"
        pattern="$loaded"
    else
        # 인자로 받은 키워드 사용 (기존 방식 유지)
        local kws=("$@")
        pattern=$(IFS='|'; echo "${kws[*]}")
    fi

    if [[ "$src" == "-" ]]; then
        grep -iE "$pattern" || true
    else
        grep -iE "$pattern" "$src" 2>/dev/null || true
    fi
}

# ── 가짜 뉴스 제외 필터 ──────────────────────────────────────────────────────
# site: 쿼리가 수집하는 스펙 문서·메뉴·챕터 페이지 등 "뉴스가 아닌 항목"을 제거한다.
# TSV(제목|URL|날짜)의 제목 필드(첫 번째 칼럼)를 검사한다.
exclude_non_news() {
    # 인자: <TSV 파일 또는 ->  /  옵션: EXCLUDE_VERBOSE=1 이면 제외 사유 출력
    local src="$1"
    python3 - "$src" <<'PYEOF'
import sys, re

EXCLUDE = re.compile(
    r'\b(about the|welcome to|copy of|join us for|press room|pressroom'
    r'|menu|search|login)\b'
    r'|(\bopen issues\b)|(\bcall for content\b)'
    r'|(specification version)',
    re.I)

with open(sys.argv[1]) as f:
    for line in f:
        line = line.rstrip('\n')
        if not line:
            continue
        title = line.split('|')[0]
        if EXCLUDE.search(title):
            print(f"[exclude_filter] 제외: {title[:60]}", file=sys.stderr)
            continue
        print(line)
PYEOF
}

# ═════════════════════════════════════════════════════════════════════════════
# 데이터 관리 함수
# ═════════════════════════════════════════════════════════════════════════════

extract_metadata() {
    # 설명: stdin 으로 받은 HTML에서 메타데이터(제목·설명·날짜·저자)를 추출해
    #       JSON 형식으로 출력한다.
    python3 - <<'PYEOF'
import sys, re, json
html = sys.stdin.read()

def first(patterns, flags=re.IGNORECASE | re.DOTALL):
    """주어진 정규식 목록 중 첫 번째로 매칭되는 그룹 1을 반환한다."""
    for p in patterns:
        m = re.search(p, html, flags)
        if m:
            return re.sub(r'<[^>]+>', '', m.group(1)).strip()
    return ''

# OG 태그 우선, 없으면 일반 title 태그 사용
title = first([
    r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)["\']',
    r'<title[^>]*>(.*?)</title>'
])
desc  = first([
    r'<meta[^>]+(?:name=["\']description["\']|property=["\']og:description["\'])'
    r'[^>]+content=["\']([^"\']+)["\']'
])
date   = first([r'(\d{4}-\d{2}-\d{2})'])  # YYYY-MM-DD 형식 날짜
author = first([r'<meta[^>]+name=["\']author["\'][^>]+content=["\']([^"\']+)["\']'])

print(json.dumps({'title': title, 'description': desc, 'date': date, 'author': author}))
PYEOF
}

save_cache() {
    # 인자: <url>
    # 설명: URL을 cache/seen_urls.txt 에 추가한다.
    #       이미 발송된 뉴스/논문 URL을 기록해 중복 발송을 방지한다.
    local url="$1"
    local cache="$SCRIPT_DIR/cache/seen_urls.txt"
    mkdir -p "$SCRIPT_DIR/cache"
    echo "$url" >> "$cache"
}

is_cached() {
    # 인자: <url>
    # 설명: URL이 캐시에 있으면 1, 없으면 0을 출력한다.
    local url="$1"
    local cache="$SCRIPT_DIR/cache/seen_urls.txt"
    # 캐시 파일이 없으면 0 반환 (미캐시 상태)
    [[ -f "$cache" ]] && grep -qF "$url" "$cache" 2>/dev/null && echo "1" || echo "0"
}

deduplicate() {
    # 인자: <tsv_파일>
    # 설명: TSV 파일의 2번째 필드(URL)를 캐시와 비교해 이미 처리된 항목을 제거한다.
    #       원본 파일을 새 내용으로 덮어씀.
    local tsv="$1"
    local cache="$SCRIPT_DIR/cache/seen_urls.txt"
    local tmp
    tmp=$(mktemp)  # 임시 파일에 결과 쌓은 후 원본 교체

    if [[ ! -f "$cache" ]]; then
        # 캐시 없으면 전체 유지
        cp "$tsv" "$tmp"
    else
        while IFS='|' read -r f1 url rest; do
            # URL이 캐시에 없는 항목만 유지
            grep -qF "$url" "$cache" 2>/dev/null || echo "${f1}|${url}|${rest}"
        done < "$tsv" >> "$tmp" || true
    fi

    cp "$tmp" "$tsv"
    rm -f "$tmp"
}

# ═════════════════════════════════════════════════════════════════════════════
# AI 함수
# ═════════════════════════════════════════════════════════════════════════════

ai_summarize() {
    # 인자: <제목> <본문>
    # 설명: AI API를 호출해 텍스트를 3줄 한국어로 요약한다. 각 줄은 • 기호로 시작한다.
    #       우선순위: Groq (무료) → Anthropic → 더미 요약
    local title="$1"
    local body="${2:-}"
    local groq_key="${GROQ_API_KEY:-}"
    local anthropic_key="${ANTHROPIC_API_KEY:-}"

    # ── OpenRouter API (무료 모델 사용) ──────────────────────────────────────
    local or_key="${OPENROUTER_API_KEY:-}"
    if [[ -n "$or_key" ]]; then
        local payload
        payload=$(python3 -c "
import json, sys
title = sys.argv[1]; body = sys.argv[2]
print(json.dumps({
    'model': 'google/gemma-4-31b-it:free',
    'messages': [
        {'role': 'system', 'content': 'MBSE 전문가로서 핵심만 3줄 한국어로 요약하세요. 각 줄은 •로 시작하세요.'},
        {'role': 'user', 'content': f'제목: {title}\n\n내용: {body[:2000]}'}
    ],
    'max_tokens': 300
}))" "$title" "$body")

        local response
        response=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $or_key" \
            --max-time 30 \
            -d "$payload" 2>/dev/null)

        python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d['choices'][0]['message']['content'].strip())
except Exception as e:
    print(f'[ai_summarize] OpenRouter 파싱 오류: {e}', file=sys.stderr)
    sys.exit(1)
" <<< "$response" && return 0
    fi

    # ── Anthropic 폴백 ────────────────────────────────────────────────────────
    if [[ -n "$anthropic_key" ]]; then
        local model="${CLAUDE_MODEL:-claude-haiku-4-5-20251001}"
        local payload
        payload=$(python3 -c "
import json, sys
title = sys.argv[1]; body = sys.argv[2]; model = sys.argv[3]
print(json.dumps({
    'model': model, 'max_tokens': 300,
    'system': 'MBSE 전문가로서 핵심만 3줄 한국어로 요약하세요. 각 줄은 •로 시작하세요.',
    'messages': [{'role': 'user', 'content': f'제목: {title}\n\n내용: {body[:2000]}'}]
}))" "$title" "$body" "$model")

        local response
        response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $anthropic_key" \
            -H "anthropic-version: 2023-06-01" \
            --max-time 30 \
            -d "$payload" 2>/dev/null)

        python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    if 'content' in d and d['content']:
        print(d['content'][0]['text'].strip())
    else:
        sys.exit(1)
except Exception as e:
    sys.exit(1)
" <<< "$response" && return 0
    fi

    # ── 더미 폴백 (API 키 없음) ───────────────────────────────────────────────
    echo "• API 키 미설정 — 요약 생략"
    echo "• GROQ_API_KEY 또는 ANTHROPIC_API_KEY 를 설정하세요"
}
export -f ai_summarize

# ═════════════════════════════════════════════════════════════════════════════
# URL 인코딩 함수
# ═════════════════════════════════════════════════════════════════════════════

urlencode() {
    # 인자: <문자열>
    # 설명: 문자열을 URL 퍼센트 인코딩으로 변환한다.
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

retry() {
    # 인자: <최대횟수> <초기지연(초)> <명령> [인자...]
    # 설명: 명령 실행에 실패하면 지수 백오프로 재시도한다.
    local max="$1" delay="$2"; shift 2
    local attempt=1

    while (( attempt <= max )); do
        "$@" && return 0  # 성공하면 즉시 반환
        echo "[retry] 시도 $attempt/$max 실패, ${delay}s 후 재시도" >&2
        sleep "$delay"
        delay=$(( delay * 2 ))  # 지수 백오프
        (( attempt++ ))
    done

    echo "[retry] 모든 시도($max회) 실패" >&2
    return 1
}

#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 파일    : skills.sh
# 설명    : 모든 bash 에이전트가 source 해서 사용하는 공유 유틸리티 함수 모음.
#           네트워크 요청, HTML/RSS 파싱, 캐시 관리, Claude API 요약,
#           텔레그램 전송 등 공통 기능을 제공한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — 네트워크·필터링·AI·텔레그램 공유 함수 구현
# ─────────────────────────────────────────────────────────────────────────────
#
# 사용법:
#   source skills.sh   (각 에이전트 스크립트 상단에서 호출)
#
# 전제 조건:
#   - curl, python3 가 PATH에 있어야 한다
#   - .env 파일에 ANTHROPIC_API_KEY, TELEGRAM_TOKEN, CHAT_ID 가 설정되어 있어야 한다

set -euo pipefail  # 오류 발생 시 즉시 종료, 미정의 변수 오류 처리

# ── 프로젝트 루트 경로 설정 ────────────────────────────────────────────────────
# 이미 SCRIPT_DIR이 설정된 경우(에이전트에서 설정) 덮어쓰지 않음
: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# ── 환경변수 로드 (.env 파일) ─────────────────────────────────────────────────
# set -a/+a 로 감싸면 .env의 변수가 자동으로 export 됨
[[ -f "$SCRIPT_DIR/.env" ]] && set -a && source "$SCRIPT_DIR/.env" && set +a

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
    local url="$1"
    local xml

    xml=$(web_fetch "$url") || return 1

    # Python으로 RSS XML 파싱 (bash의 XML 파싱 능력이 제한적이므로)
    echo "$xml" | python3 - <<'PYEOF'
import sys, xml.etree.ElementTree as ET, re
try:
    root = ET.fromstring(sys.stdin.read())
    for item in root.findall('.//item'):
        t = item.find('title')
        l = item.find('link')
        d = item.find('pubDate') or item.find('dc:date',
                {'dc': 'http://purl.org/dc/elements/1.1/'})
        # 파이프(|)는 TSV 구분자이므로 제목에서 제거
        title = re.sub(r'<[^>]+>', '', (t.text or '')).strip().replace('|', '-') if t is not None else ''
        link  = (l.text or '').strip() if l is not None else ''
        date  = (d.text or '').strip() if d is not None else ''
        if title and link:
            print(f"{title}|{link}|{date}")
except Exception as e:
    print(f"[fetch_rss] 파싱 오류: {e}", file=sys.stderr)
PYEOF
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
# 필터링 함수
# ═════════════════════════════════════════════════════════════════════════════

filter_keywords() {
    # 인자: <파일경로 또는 -> [키워드 ...]
    # 설명: 파일(또는 stdin)에서 MBSE 관련 키워드가 포함된 행만 출력한다.
    #       grep -i 로 대소문자 무관하게 필터링한다.
    local src="$1"; shift
    # 키워드 인자가 없으면 기본 MBSE 키워드 목록 사용
    local kws=("${@:-MBSE SysML UAF digital.twin systems.engineering Cameo model-based INCOSE DoDAF UPDM Capella}")
    local pattern
    # OR 패턴으로 결합: MBSE|SysML|UAF|...
    pattern=$(IFS='|'; echo "${kws[*]}")

    if [[ "$src" == "-" ]]; then
        grep -iE "$pattern" || true  # stdin에서 읽기
    else
        grep -iE "$pattern" "$src" 2>/dev/null || true  # 파일에서 읽기
    fi
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

claude_summarize() {
    # 인자: <텍스트>
    # 설명: Anthropic Claude API를 호출해 텍스트를 3줄 한국어로 요약한다.
    #       각 줄은 • 기호로 시작한다.
    local text="$1"
    local model="${CLAUDE_MODEL:-claude-haiku-4-5-20251001}"
    local api_key="${ANTHROPIC_API_KEY:-}"

    [[ -z "$api_key" ]] && {
        echo "[claude_summarize] ANTHROPIC_API_KEY 미설정" >&2
        return 1
    }

    # Python으로 JSON 페이로드 안전하게 생성 (특수문자 이스케이프)
    local payload
    payload=$(python3 -c "
import json, sys
text  = sys.argv[1]
model = sys.argv[2]
payload = {
    'model': model,
    'max_tokens': 300,
    'system': '당신은 MBSE 전문가입니다. 핵심만 3줄로 요약하세요. 각 줄은 •로 시작하세요.',
    'messages': [{'role': 'user', 'content': text}]
}
print(json.dumps(payload))
" "$text" "$model")

    # Claude API 호출
    local response
    response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $api_key" \
        -H "anthropic-version: 2023-06-01" \
        --max-time 30 \
        -d "$payload" 2>/dev/null)

    # 응답 JSON에서 텍스트 내용 추출
    python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    if 'content' in d and d['content']:
        print(d['content'][0]['text'].strip())
    else:
        err = d.get('error', {}).get('message', '알 수 없는 오류')
        print(f'오류: {err}', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'파싱 오류: {e}', file=sys.stderr)
    sys.exit(1)
" <<< "$response"
}

# ═════════════════════════════════════════════════════════════════════════════
# 텔레그램 함수
# ═════════════════════════════════════════════════════════════════════════════

urlencode() {
    # 인자: <문자열>
    # 설명: 문자열을 URL 퍼센트 인코딩으로 변환한다.
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

mdv2_escape() {
    # 인자: <텍스트>
    # 설명: 텔레그램 MarkdownV2 형식의 특수문자를 이스케이프 처리한다.
    #       링크 구문([text](url)) 내부가 아닌 일반 텍스트에만 적용할 것.
    python3 -c "
import sys
text = sys.argv[1]
special = r'_*[]()~\`>#+=|{}.!'  # MarkdownV2 이스케이프 대상 문자
escaped = ''
for ch in text:
    escaped += ('\\\\' + ch) if ch in special else ch
print(escaped)
" "$1"
}

send_telegram() {
    # 인자: <메시지>
    # 설명: 텔레그램 봇 API로 메시지를 전송한다.
    #       DRY_RUN=1 환경변수가 설정된 경우 실제 전송 없이 메시지만 출력한다.
    local msg="$1"
    local token="${TELEGRAM_TOKEN:-}"
    local chat_id="${CHAT_ID:-}"
    local dry="${DRY_RUN:-0}"

    if [[ "$dry" == "1" ]]; then
        # 테스트 모드: 실제 전송 대신 콘솔에 출력
        echo "─────────────────────────────────────" >&2
        echo "[DRY-RUN] 텔레그램 발송 미리보기:" >&2
        echo "$msg" >&2
        echo "─────────────────────────────────────" >&2
        return 0
    fi

    [[ -z "$token" || -z "$chat_id" ]] && {
        echo "[send_telegram] TELEGRAM_TOKEN 또는 CHAT_ID 미설정" >&2
        return 1
    }

    # URL 인코딩 후 POST 요청
    local encoded
    encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$msg")

    curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        --max-time 30 \
        -d "chat_id=${chat_id}&text=${encoded}&parse_mode=MarkdownV2" | \
        python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
if not d.get('ok'):
    print(f'[send_telegram] 오류: {d}', file=sys.stderr)
    sys.exit(1)
print('[send_telegram] 전송 성공')
"
}

retry() {
    # 인자: <최대횟수> <초기지연(초)> <명령> [인자...]
    # 설명: 명령 실행에 실패하면 지수 백오프로 재시도한다.
    #       예: retry 3 5 send_telegram "$msg"  → 최대 3회, 5→10→20초 간격으로 재시도
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

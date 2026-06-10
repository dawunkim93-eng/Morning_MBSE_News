#!/usr/bin/env bash
# skills.sh — shared utility functions for all MBSE bot agents
# Usage: source skills.sh  (from any agent script)
set -euo pipefail

# Resolve project root (Morning_MBSE_News/) regardless of where this file is sourced from
: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Load .env if present
[[ -f "$SCRIPT_DIR/.env" ]] && set -a && source "$SCRIPT_DIR/.env" && set +a

# ─── Network ───────────────────────────────────────────────────────────────

web_fetch() {
    # web_fetch <url> — curl with 3 retries, returns raw body
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
        echo "[web_fetch] attempt $attempt failed for $url, retry in ${delay}s" >&2
        sleep "$delay"
        delay=$((delay * 2))
    done
    echo "[web_fetch] ERROR: all retries exhausted for $url" >&2
    return 1
}

fetch_rss() {
    # fetch_rss <url> — returns TSV: title|url|date  (one item per line)
    local url="$1"
    local xml
    xml=$(web_fetch "$url") || return 1
    echo "$xml" | python3 - <<'PYEOF'
import sys, xml.etree.ElementTree as ET, re
try:
    root = ET.fromstring(sys.stdin.read())
    # RSS 2.0
    for item in root.findall('.//item'):
        t  = item.find('title')
        l  = item.find('link')
        d  = item.find('pubDate') or item.find('dc:date', {'dc': 'http://purl.org/dc/elements/1.1/'})
        title = re.sub(r'<[^>]+>','', (t.text or '')).strip().replace('|','-') if t is not None else ''
        link  = (l.text or '').strip() if l is not None else ''
        date  = (d.text or '').strip() if d is not None else ''
        if title and link:
            print(f"{title}|{link}|{date}")
except Exception as e:
    print(f"[fetch_rss] parse error: {e}", file=sys.stderr)
PYEOF
}

parse_html() {
    # parse_html <selector> — reads HTML from stdin, returns matched text lines
    local selector="$1"
    python3 - "$selector" <<'PYEOF'
import sys, re
selector = sys.argv[1]
html = sys.stdin.read()
# Derive tag + class/id from simple selectors
tag_m   = re.match(r'^([a-zA-Z]+)', selector)
class_m = re.search(r'\.([\w-]+)', selector)
id_m    = re.search(r'#([\w-]+)', selector)
tag = tag_m.group(1) if tag_m else r'\w+'
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

# ─── Filtering ────────────────────────────────────────────────────────────

filter_keywords() {
    # filter_keywords <file|-> [keyword ...] — grep for MBSE terms; reads stdin if file is -
    local src="$1"; shift
    local kws=("${@:-MBSE SysML UAF digital.twin systems.engineering Cameo model-based INCOSE DoDAF UPDM Capella}")
    local pattern
    pattern=$(IFS='|'; echo "${kws[*]}")
    if [[ "$src" == "-" ]]; then
        grep -iE "$pattern" || true
    else
        grep -iE "$pattern" "$src" 2>/dev/null || true
    fi
}

# ─── Data ─────────────────────────────────────────────────────────────────

extract_metadata() {
    # extract_metadata — reads HTML from stdin, prints JSON
    python3 - <<'PYEOF'
import sys, re, json
html = sys.stdin.read()
def first(patterns, flags=re.IGNORECASE|re.DOTALL):
    for p in patterns:
        m = re.search(p, html, flags)
        if m: return re.sub(r'<[^>]+>','',m.group(1)).strip()
    return ''
title = first([r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)["\']',
               r'<title[^>]*>(.*?)</title>'])
desc  = first([r'<meta[^>]+(?:name=["\']description["\']|property=["\']og:description["\'])'
               r'[^>]+content=["\']([^"\']+)["\']'])
date  = first([r'(\d{4}-\d{2}-\d{2})'])
author= first([r'<meta[^>]+name=["\']author["\'][^>]+content=["\']([^"\']+)["\']'])
print(json.dumps({'title':title,'description':desc,'date':date,'author':author}))
PYEOF
}

save_cache() {
    # save_cache <url> — append URL to cache/seen_urls.txt
    local url="$1"
    local cache="$SCRIPT_DIR/cache/seen_urls.txt"
    mkdir -p "$SCRIPT_DIR/cache"
    echo "$url" >> "$cache"
}

is_cached() {
    # is_cached <url> — prints 1 if cached, 0 otherwise
    local url="$1"
    local cache="$SCRIPT_DIR/cache/seen_urls.txt"
    [[ -f "$cache" ]] && grep -qF "$url" "$cache" 2>/dev/null && echo "1" || echo "0"
}

deduplicate() {
    # deduplicate <tsv_file> — remove rows whose URL (field 2) is in cache
    local tsv="$1"
    local cache="$SCRIPT_DIR/cache/seen_urls.txt"
    local tmp
    tmp=$(mktemp)
    if [[ ! -f "$cache" ]]; then
        cp "$tsv" "$tmp"
    else
        while IFS='|' read -r f1 url rest; do
            grep -qF "$url" "$cache" 2>/dev/null || echo "${f1}|${url}|${rest}"
        done < "$tsv" >> "$tmp" || true
    fi
    cp "$tmp" "$tsv"
    rm -f "$tmp"
}

# ─── AI ───────────────────────────────────────────────────────────────────

claude_summarize() {
    # claude_summarize <text> — returns 3-line Korean summary
    local text="$1"
    local model="${CLAUDE_MODEL:-claude-haiku-4-5-20251001}"
    local api_key="${ANTHROPIC_API_KEY:-}"
    [[ -z "$api_key" ]] && { echo "[claude_summarize] ANTHROPIC_API_KEY not set" >&2; return 1; }

    local payload
    payload=$(python3 -c "
import json, sys
text = sys.argv[1]
model = sys.argv[2]
payload = {
    'model': model,
    'max_tokens': 300,
    'system': '당신은 MBSE 전문가입니다. 핵심만 3줄로 요약하세요. 각 줄은 •로 시작하세요.',
    'messages': [{'role': 'user', 'content': text}]
}
print(json.dumps(payload))
" "$text" "$model")

    local response
    response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $api_key" \
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
        print(d.get('error',{}).get('message','unknown error'), file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'parse error: {e}', file=sys.stderr)
    sys.exit(1)
" <<< "$response"
}

# ─── Telegram ─────────────────────────────────────────────────────────────

urlencode() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

mdv2_escape() {
    # mdv2_escape <text> — escape special chars for MarkdownV2 (plain text only, not inside links)
    python3 -c "
import re, sys
text = sys.argv[1]
# Escape all MarkdownV2 special chars outside of link syntax
special = r'_*[]()~\`>#+=|{}.!'
escaped = ''
for ch in text:
    if ch in special:
        escaped += '\\\\' + ch
    else:
        escaped += ch
print(escaped)
" "$1"
}

send_telegram() {
    # send_telegram <message> — POST to Telegram; respects DRY_RUN=1
    local msg="$1"
    local token="${TELEGRAM_TOKEN:-}"
    local chat_id="${CHAT_ID:-}"
    local dry="${DRY_RUN:-0}"

    if [[ "$dry" == "1" ]]; then
        echo "─────────────────────────────────────" >&2
        echo "[DRY-RUN] Telegram message:" >&2
        echo "$msg" >&2
        echo "─────────────────────────────────────" >&2
        return 0
    fi

    [[ -z "$token" || -z "$chat_id" ]] && {
        echo "[send_telegram] TELEGRAM_TOKEN or CHAT_ID not set" >&2; return 1
    }

    local encoded
    encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$msg")

    curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        --max-time 30 \
        -d "chat_id=${chat_id}&text=${encoded}&parse_mode=MarkdownV2" | \
        python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
if not d.get('ok'):
    print(f'[send_telegram] ERROR: {d}', file=sys.stderr)
    sys.exit(1)
print('[send_telegram] OK')
"
}

retry() {
    # retry <max> <delay_sec> <cmd> [args...] — exponential backoff
    local max="$1" delay="$2"; shift 2
    local attempt=1
    while (( attempt <= max )); do
        "$@" && return 0
        echo "[retry] attempt $attempt/$max failed, waiting ${delay}s" >&2
        sleep "$delay"
        delay=$(( delay * 2 ))
        (( attempt++ ))
    done
    echo "[retry] all $max attempts failed" >&2
    return 1
}

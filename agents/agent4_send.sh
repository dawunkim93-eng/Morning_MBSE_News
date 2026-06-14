#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 파일    : agents/agent4_send.sh
# 설명    : 텔레그램 발송·캐시 저장·로그 기록 에이전트.
#           Phase 2 에서 만들어진 요약 JSON을 HTML 형식으로 변환하고
#           텔레그램으로 발송한다. 발송 성공 후 URL을 캐시에 저장하고
#           로그 파일에 실행 결과를 기록한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — MarkdownV2 포맷, 텔레그램 발송, 캐시/로그 구현
#   v1.1   2026-06-12   버그 수정 — mdv2() 특수문자 목록에 '-' 추가 (400 에러 수정)
#   v1.2   2026-06-13   버그 수정 — HTTPError 시 Telegram 응답 본문 출력, urllib.error 추가
#   v1.3   2026-06-14   포맷 변경 — MarkdownV2 → HTML (이스케이프 단순화, 400 오류 방지)
# ─────────────────────────────────────────────────────────────────────────────
#
# 입력:
#   /tmp/summary_results.json (agent3 출력)
#
# 출력:
#   텔레그램 메시지 발송
#   cache/seen_urls.txt — 발송된 URL 추가
#   logs/YYYY-MM-DD.log — 실행 결과 기록

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/skills.sh"

# ── 설정 ────────────────────────────────────────────────────────────────────
INPUT="$SHARED_TMP/summary_results.json"   # agent3 출력 파일
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"  # 날짜별 로그 파일

echo "[agent4] 텔레그램 메시지 포맷 및 발송..." >&2

# ── 핵심 로직: Python 인라인 스크립트 ─────────────────────────────────────────
python3 - "$INPUT" \
          "${DRY_RUN:-0}" \
          "${TELEGRAM_TOKEN:-}" \
          "${CHAT_ID:-}" \
          "$LOG_FILE" \
          "$SCRIPT_DIR/cache/seen_urls.txt" <<'PYEOF'
import sys, json, re, urllib.request, urllib.parse, urllib.error, datetime

# 인자 파싱
input_path = sys.argv[1]
dry_run    = sys.argv[2] == "1"
token      = sys.argv[3]
chat_id    = sys.argv[4]
log_file   = sys.argv[5]
cache_file = sys.argv[6]

# ── HTML 이스케이프 유틸리티 ──────────────────────────────────────────────────
# HTML 모드는 <, >, & 세 글자만 이스케이프하면 되어 MarkdownV2보다 훨씬 안정적이다.

def html_escape(text: str) -> str:
    """일반 텍스트를 Telegram HTML 모드용으로 이스케이프한다."""
    return text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

def html_link(title: str, url: str) -> str:
    """HTML 링크 <a href="URL">제목</a> 을 생성한다."""
    safe_title = html_escape(title)
    safe_url   = url.replace('"', '%22')
    return f'<a href="{safe_url}">{safe_title}</a>'

def first_line(summary: str) -> str:
    """요약 텍스트의 첫 번째 비어있지 않은 줄을 반환한다."""
    for line in summary.splitlines():
        line = line.strip()
        if line:
            return line
    return ''

# ── 데이터 로드 ───────────────────────────────────────────────────────────────
with open(input_path) as f:
    data = json.load(f)

news   = data.get("news",   [])
papers = data.get("papers", [])
today  = datetime.date.today().isoformat()  # YYYY-MM-DD

# ── 메시지 조립 ───────────────────────────────────────────────────────────────
# HTML 형식으로 헤더, 뉴스 섹션, 논문 섹션을 구성
lines = [
    f"🛰 <b>MBSE 데일리 브리핑</b> — {html_escape(today)}",
    "",
]

# 뉴스 섹션
if news:
    lines.append(f"<b>📰 뉴스 ({len(news)}건)</b>")
    for i, item in enumerate(news, 1):
        cat     = html_escape(f"#{item.get('category', '')}")
        link    = html_link(item['title'], item['url'])
        summary = html_escape(first_line(item.get('summary', '')))
        lines.append(f"{i}. {link} {cat}")
        if summary:
            lines.append(f"   └ {summary}")
    lines.append("")

# 논문 섹션
if papers:
    lines.append(f"<b>📄 논문 ({len(papers)}건)</b>")
    for i, item in enumerate(papers, 1):
        cat     = html_escape(f"#{item.get('category', '')}")
        link    = html_link(item['title'], item['url'])
        summary = html_escape(first_line(item.get('summary', '')))
        lines.append(f"{i}. {link} {cat}")
        if summary:
            lines.append(f"   └ {summary}")
    lines.append("")

lines.append("<i>Powered by Claude</i>")
message = "\n".join(lines)  # 완성된 HTML 메시지

# ── 텔레그램 발송 ─────────────────────────────────────────────────────────────
status = "skipped"

if dry_run:
    # 테스트 모드: 실제 발송 없이 메시지 미리보기만 출력
    print("─" * 50, file=sys.stderr)
    print("[DRY-RUN] 텔레그램 발송 미리보기:", file=sys.stderr)
    print(message, file=sys.stderr)
    print("─" * 50, file=sys.stderr)
    status = "dry-run"

elif not token or not chat_id:
    print("[agent4] 오류: TELEGRAM_TOKEN 또는 CHAT_ID 미설정", file=sys.stderr)
    sys.exit(1)

else:
    # 실제 발송: 최대 3회 재시도, 실패마다 대기 시간 증가
    encoded = urllib.parse.quote(message)
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=f"chat_id={chat_id}&text={encoded}&parse_mode=HTML".encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST"
    )
    max_retries = 3
    for attempt in range(1, max_retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                result = json.loads(resp.read())
                if result.get("ok"):
                    status = "sent"
                    print(f"[agent4] 텔레그램 발송 성공", file=sys.stderr)
                    break
                else:
                    raise RuntimeError(f"API 오류: {result}")
        except urllib.error.HTTPError as http_err:
            # HTTP 4xx/5xx — 실제 Telegram API 에러 메시지를 읽어 출력
            body = http_err.read().decode("utf-8", errors="replace")
            print(f"[agent4] 시도 {attempt}/{max_retries} 실패 "
                  f"(HTTP {http_err.code}): {body}", file=sys.stderr)
            if attempt == max_retries:
                sys.exit(1)
            import time
            time.sleep(5 * attempt)
        except Exception as e:
            print(f"[agent4] 시도 {attempt}/{max_retries} 실패: {e}", file=sys.stderr)
            if attempt == max_retries:
                sys.exit(1)
            import time
            time.sleep(5 * attempt)

# ── URL 캐시 저장 ────────────────────────────────────────────────────────────
# 발송 성공 또는 DRY-RUN 시 URL을 캐시에 저장 (다음 실행 시 중복 방지)
if status in ("sent", "dry-run"):
    import os
    os.makedirs(os.path.dirname(cache_file), exist_ok=True)
    with open(cache_file, "a") as f:
        for item in news + papers:
            f.write(item["url"] + "\n")
    print(f"[agent4] URL {len(news)+len(papers)}건 캐시 저장 완료", file=sys.stderr)

# ── 실행 결과 로그 기록 ───────────────────────────────────────────────────────
ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
with open(log_file, "a") as f:
    f.write(f"[{ts}] status={status} news={len(news)} papers={len(papers)}\n")

print(f"[agent4] 완료 — status={status}", file=sys.stderr)
PYEOF

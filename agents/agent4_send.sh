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
import sys, json, urllib.request, urllib.parse, urllib.error, datetime, os, time

# 인자 파싱
input_path = sys.argv[1]
dry_run    = sys.argv[2] == "1"
token      = sys.argv[3]
chat_id    = sys.argv[4]
log_file   = sys.argv[5]
cache_file = sys.argv[6]

def html_escape(t: str) -> str:
    return t.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')

def html_link(title: str, url: str) -> str:
    return f'<a href="{url.replace(chr(34),"%22")}">{html_escape(title)}</a>'

def date_str_to_kr(s: str) -> str:
    try: y, m, d = s.split('-'); return f"{int(m)}월 {int(d)}일"
    except: return s

def format_paper(item: dict) -> list:
    out = []
    date_kr = item.get('date_kr') or date_str_to_kr(item.get('date', ''))
    out.append(f"<b>{html_escape(item['title'])}</b> ({date_kr} 제출)")
    out.append("")
    summary = item.get('summary', '').strip()
    if summary:
        out.append(html_escape(summary))
        out.append("")
    if item.get('authors'):
        out.append(f"저자: {html_escape(item['authors'])}")
    out.append(f"원문: {item.get('url','')}")
    return out

# ── 데이터 로드 ───────────────────────────────────────────────────────────────
with open(input_path) as f:
    data = json.load(f)

report_date_kr   = data.get('report_date_kr', '')
window_start_kst = data.get('window_start_kst', '')
window_end_kst   = data.get('window_end_kst',   '')
today_news       = data.get('today_news',    [])
fallback_news    = data.get('fallback_news', [])
today_papers     = data.get('today_papers',  [])
fallback_papers  = data.get('fallback_papers', [])

# ── 메시지 조립 ───────────────────────────────────────────────────────────────
lines = [f"🛰 <b>MBSE 일일 브리핑</b> — {html_escape(report_date_kr)}", ""]

# 뉴스 섹션
lines.append("<b>📰 뉴스</b>")
lines.append("")
if today_news:
    for i, item in enumerate(today_news, 1):
        link = html_link(item['title'], item['url'])
        cat  = html_escape(f"#{item.get('category','')}")
        lines.append(f"{i}. {link} {cat}")
        summ = next((l.strip() for l in item.get('summary','').splitlines() if l.strip()), '')
        if summ:
            lines.append(f"   └ {html_escape(summ)}")
    lines.append("")
else:
    ws_kr = date_str_to_kr(window_start_kst) + " 오전 07:00"
    we_kr = date_str_to_kr(window_end_kst)   + " 오전 07:00"
    lines.append(f"오늘은 {ws_kr}부터 {we_kr} (KST) 사이에 새롭게 발표된 MBSE 관련 뉴스가 없습니다.")
    lines.append("")
    if fallback_news:
        mentions = []
        for item in fallback_news[:2]:
            d_kr = item.get('date_kr') or date_str_to_kr(item.get('date',''))
            mentions.append(f"{html_link(item['title'], item['url'])}({d_kr})")
        fb_str = f"{mentions[0]}와 {mentions[1]}" if len(mentions) > 1 else mentions[0]
        lines.append(f"참고로, 최근 주목할 만한 MBSE 관련 소식으로는 {fb_str} 정도가 있으나, 이는 당일 범위 밖의 내용입니다.")
    lines.append("")

# 논문 섹션
lines.append("<b>📄 arxiv 신규 논문</b>")
lines.append("")
if today_papers:
    for item in today_papers:
        lines.extend(format_paper(item))
        lines.append("")
elif fallback_papers:
    lines.append("어제~오늘 범위 내 신규 논문은 없으나, 이번 달 가장 최근에 등록된 MBSE 관련 논문 1건을 아래에 안내합니다.")
    lines.append("")
    lines.extend(format_paper(fallback_papers[0]))
    lines.append("")
else:
    lines.append("오늘은 새로운 MBSE 관련 논문이 없습니다.")

lines.append("<i>Powered by OpenRouter · 매일 오전 07:00 KST</i>")
message = "\n".join(lines)

# ── 텔레그램 발송 ─────────────────────────────────────────────────────────────
status = "skipped"
if dry_run:
    print("─" * 50, file=sys.stderr)
    print("[DRY-RUN] 텔레그램 발송 미리보기:", file=sys.stderr)
    print(message, file=sys.stderr)
    print("─" * 50, file=sys.stderr)
    status = "dry-run"
elif not token or not chat_id:
    print("[agent4] 오류: TELEGRAM_TOKEN 또는 CHAT_ID 미설정", file=sys.stderr)
    sys.exit(1)
else:
    encoded = urllib.parse.quote(message)
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=f"chat_id={chat_id}&text={encoded}&parse_mode=HTML".encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST"
    )
    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                if json.loads(resp.read()).get("ok"):
                    status = "sent"
                    print("[agent4] 텔레그램 발송 성공", file=sys.stderr)
                    break
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            print(f"[agent4] 시도 {attempt}/3 실패 (HTTP {e.code}): {body}", file=sys.stderr)
            if attempt == 3: sys.exit(1)
            time.sleep(5 * attempt)
        except Exception as e:
            print(f"[agent4] 시도 {attempt}/3 실패: {e}", file=sys.stderr)
            if attempt == 3: sys.exit(1)
            time.sleep(5 * attempt)

# ── URL 캐시 저장 (오늘 항목만) ─────────────────────────────────────────────
if status in ("sent", "dry-run"):
    today_urls = [i["url"] for i in today_news + today_papers]
    if today_urls:
        os.makedirs(os.path.dirname(cache_file), exist_ok=True)
        with open(cache_file, "a") as f:
            for url in today_urls: f.write(url + "\n")
        print(f"[agent4] URL {len(today_urls)}건 캐시 저장 완료", file=sys.stderr)

# ── 실행 결과 로그 기록 ───────────────────────────────────────────────────────
ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
n  = len(today_news) or len(fallback_news)
p  = len(today_papers) or len(fallback_papers)
with open(log_file, "a") as f:
    f.write(f"[{ts}] status={status} news={n}({'today' if today_news else 'fallback'}) papers={p}({'today' if today_papers else 'fallback'})\n")

print(f"[agent4] 완료 — status={status}", file=sys.stderr)
PYEOF

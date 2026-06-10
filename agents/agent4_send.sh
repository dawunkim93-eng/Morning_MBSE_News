#!/usr/bin/env bash
# agent4_send.sh — format MarkdownV2 + send Telegram + cache + log
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/skills.sh"

INPUT="/tmp/summary_results.json"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"

echo "[agent4] Formatting and sending..." >&2

python3 - "$INPUT" "${DRY_RUN:-0}" "${TELEGRAM_TOKEN:-}" "${CHAT_ID:-}" \
          "$LOG_FILE" "$SCRIPT_DIR/cache/seen_urls.txt" <<'PYEOF'
import sys, json, re, urllib.request, urllib.parse, datetime

input_path = sys.argv[1]
dry_run    = sys.argv[2] == "1"
token      = sys.argv[3]
chat_id    = sys.argv[4]
log_file   = sys.argv[5]
cache_file = sys.argv[6]

def mdv2(text: str) -> str:
    """Escape text for Telegram MarkdownV2 (plain text segments)."""
    special = r'\_*[]()~`>#+=|{}.!'
    result = ''
    for ch in text:
        if ch in special:
            result += '\\' + ch
        else:
            result += ch
    return result

def mdv2_link(title: str, url: str) -> str:
    """[escaped title](url) — URL needs minimal escaping."""
    safe_title = title.replace('[','\\[').replace(']','\\]')
    safe_url   = url.replace(')', '\\)')
    return f"[{safe_title}]({safe_url})"

def first_line(summary: str) -> str:
    for line in summary.splitlines():
        line = line.strip()
        if line:
            return line
    return ''

with open(input_path) as f:
    data = json.load(f)

news   = data.get("news",   [])
papers = data.get("papers", [])
today  = datetime.date.today().isoformat()

# ── Build message ──────────────────────────────────────────────────────────
lines = [
    f"🛰 *MBSE 데일리 브리핑* — {mdv2(today)}",
    "",
]

if news:
    lines.append(f"*📰 뉴스 \\({len(news)}건\\)*")
    for i, item in enumerate(news, 1):
        cat     = mdv2(f"#{item.get('category','')}")
        link    = mdv2_link(item['title'], item['url'])
        summary = mdv2(first_line(item.get('summary', '')))
        lines.append(f"{i}\\. {link} {cat}")
        if summary:
            lines.append(f"   └ {summary}")
    lines.append("")

if papers:
    lines.append(f"*📄 논문 \\({len(papers)}건\\)*")
    for i, item in enumerate(papers, 1):
        cat     = mdv2(f"#{item.get('category','')}")
        link    = mdv2_link(item['title'], item['url'])
        summary = mdv2(first_line(item.get('summary', '')))
        lines.append(f"{i}\\. {link} {cat}")
        if summary:
            lines.append(f"   └ {summary}")
    lines.append("")

lines.append("_Powered by Claude_")
message = "\n".join(lines)

# ── Send ───────────────────────────────────────────────────────────────────
status = "skipped (dry-run)"

if dry_run:
    print("─" * 50, file=sys.stderr)
    print("[DRY-RUN] Telegram message preview:", file=sys.stderr)
    print(message, file=sys.stderr)
    print("─" * 50, file=sys.stderr)
    status = "dry-run"
elif not token or not chat_id:
    print("[agent4] ERROR: TELEGRAM_TOKEN or CHAT_ID missing", file=sys.stderr)
    sys.exit(1)
else:
    encoded = urllib.parse.quote(message)
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=f"chat_id={chat_id}&text={encoded}&parse_mode=MarkdownV2".encode(),
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
                    print(f"[agent4] Telegram: OK", file=sys.stderr)
                    break
                else:
                    raise RuntimeError(f"API error: {result}")
        except Exception as e:
            print(f"[agent4] attempt {attempt}/{max_retries} failed: {e}", file=sys.stderr)
            if attempt == max_retries:
                sys.exit(1)
            import time; time.sleep(5 * attempt)

# ── Save cache ─────────────────────────────────────────────────────────────
if status in ("sent", "dry-run"):
    import os
    os.makedirs(os.path.dirname(cache_file), exist_ok=True)
    with open(cache_file, "a") as f:
        for item in news + papers:
            f.write(item["url"] + "\n")
    print(f"[agent4] Cached {len(news)+len(papers)} URLs", file=sys.stderr)

# ── Log ────────────────────────────────────────────────────────────────────
ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
with open(log_file, "a") as f:
    f.write(f"[{ts}] status={status} news={len(news)} papers={len(papers)}\n")

print(f"[agent4] Done — status={status}", file=sys.stderr)
PYEOF

#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 파일    : agents/agent4_commit.sh
# 설명    : 데이터 저장·캐시 갱신·로그 기록 에이전트.
#           Phase 2 에서 만들어진 요약 JSON을 사이트용 데이터 파일로 저장한다.
#           텔레그램 발송은 폐지되었으며, 결과는 data/ 폴더의 날짜별 JSON으로
#           커밋되어 GitHub Pages 사이트에서 소비된다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-09-26   최초 작성 — 텔레그램 발송(agent4_send.sh)을 데이터 저장으로 전환,
#                        data/YYYY-MM-DD.json 저장, 캐시/로그 기능 유지
# ─────────────────────────────────────────────────────────────────────────────
#
# 입력:
#   /tmp/summary_results.json (agent3 출력)
#
# 출력:
#   data/YYYY-MM-DD.json — 사이트용 일일 브리핑 데이터
#   cache/seen_urls.txt  — 처리된 URL 추가
#   logs/YYYY-MM-DD.log  — 실행 결과 기록

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/skills.sh"

# ── 설정 ────────────────────────────────────────────────────────────────────
INPUT="$SHARED_TMP/summary_results.json"   # agent3 출력 파일
LOG_DIR="$SCRIPT_DIR/logs"
DATA_DIR="$SCRIPT_DIR/data"
mkdir -p "$LOG_DIR" "$DATA_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"  # 날짜별 로그 파일

echo "[agent4] 브리핑 데이터 저장..." >&2

# ── 핵심 로직: Python 인라인 스크립트 ─────────────────────────────────────────
python3 - "$INPUT" \
          "${DRY_RUN:-0}" \
          "$LOG_FILE" \
          "$DATA_DIR" \
          "$SCRIPT_DIR/cache/seen_urls.txt" <<'PYEOF'
import sys, json, datetime, os

# 인자 파싱
input_path = sys.argv[1]
dry_run    = sys.argv[2] == "1"
log_file   = sys.argv[3]
data_dir   = sys.argv[4]
cache_file = sys.argv[5]

# ── 데이터 로드 ───────────────────────────────────────────────────────────────
with open(input_path) as f:
    data = json.load(f)

report_date     = data.get('report_date', datetime.date.today().isoformat())
today_news      = data.get('today_news',    [])
fallback_news   = data.get('fallback_news', [])
today_papers    = data.get('today_papers',  [])
fallback_papers = data.get('fallback_papers', [])

# ── 사이트용 데이터 파일 저장 ──────────────────────────────────────────────────
# 구조: data/YYYY-MM-DD.json  (오늘 항목 + 폴백 항목 모두 포함)
# 사이트(React+Vite)가 이 파일을 읽어 브리핑·아카이브를 렌더링한다.
output_path = os.path.join(data_dir, f"{report_date}.json")

# 저장하는 항목 구조 정규화 — 사이트에서 필요한 필드만 남김
def normalize_news(item: dict) -> dict:
    return {
        'title':    item.get('title', ''),
        'url':      item.get('url', ''),
        'date':     item.get('date', ''),
        'source':   item.get('source', 'news'),
        'category': item.get('category', 'Research'),
        'score':    item.get('score', 0),
        'summary':  item.get('summary', ''),
        'is_today': bool(item in today_news),  # 폴백 항목 구분용
    }

def normalize_paper(item: dict) -> dict:
    return {
        'title':    item.get('title', ''),
        'url':      item.get('url', ''),
        'date':     item.get('date', ''),
        'authors':  item.get('authors', ''),
        'source':   item.get('source', 'arxiv'),
        'category': item.get('category', 'Research'),
        'score':    item.get('score', 0),
        'abstract': item.get('abstract', ''),
        'summary':  item.get('summary', ''),
        'is_today': bool(item in today_papers),
    }

site_data = {
    'report_date':     report_date,
    'report_date_kr':  data.get('report_date_kr', ''),
    'window_start_kst': data.get('window_start_kst', ''),
    'window_end_kst':  data.get('window_end_kst', ''),
    'generated_at':    datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S%z'),
    'news':   [normalize_news(i)  for i in today_news + fallback_news],
    'papers': [normalize_paper(i) for i in today_papers + fallback_papers],
}

status = "skipped"
if dry_run:
    print("─" * 50, file=sys.stderr)
    print(f"[DRY-RUN] 데이터 저장 미리보기 → {output_path}", file=sys.stderr)
    print(f"  뉴스 {len(site_data['news'])}건, 논문 {len(site_data['papers'])}건", file=sys.stderr)
    print("─" * 50, file=sys.stderr)
    status = "dry-run"
else:
    os.makedirs(data_dir, exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(site_data, f, ensure_ascii=False, indent=2)
    status = "saved"
    print(f"[agent4] 데이터 저장 완료 → {output_path}", file=sys.stderr)
    print(f"[agent4] 뉴스 {len(site_data['news'])}건, 논문 {len(site_data['papers'])}건", file=sys.stderr)

# ── URL 캐시 저장 (오늘 항목만 — 폴백 항목은 재수집 대상으로 남김) ───────────────
if status in ("saved", "dry-run"):
    today_urls = [i["url"] for i in today_news + today_papers if i.get("url")]
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
    f.write(f"[{ts}] status={status} news={n}({'today' if today_news else 'fallback'}) papers={p}({'today' if today_papers else 'fallback'}) file={os.path.basename(output_path)}\n")

print(f"[agent4] 완료 — status={status}", file=sys.stderr)
PYEOF
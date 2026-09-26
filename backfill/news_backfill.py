#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────────
# 파일    : backfill/news_backfill.py
# 설명    : 뉴스 히스토리 백필 스크립트.
#           1) Google News RSS site: 쿼리에 after:/before: 연산자를 조합해
#              INCOSE·OMG 사이트 뉴스를 기간별로 수집 (Cloudflare 우회)
#           2) OMG pressroom(omg.org/news/pressroom.htm)을 직접 파싱해
#              공식 보도자료 전체를 수집
#
#           출력: data/news_archive/YYYY-MM.json (월별 파일)
#                 + data/news-index.json (전체 요약 인덱스)
#
# 사용법:
#   python3 backfill/news_backfill.py [--start 2026-06-10] [--delay 3]
#
#   --start : 수집 시작일 (YYYY-MM-DD). 기본값: 레포 시작일 2026-06-10
#
# 주의:
#   - Google News RSS는 과거 기간에 대해 색인된 항목만 반환하므로
#     뉴스 백필은 가능한 범위까지 수집한다 (누락 가능).
#   - OMG pressroom 아카이브는 전 기간 수집 가능.
#   - 백필 항목은 AI 한국어 요약 없이 원문 발췌만 저장한다.
# ─────────────────────────────────────────────────────────────────────────────

import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
CACHE_FILE = BASE_DIR / "cache" / "seen_urls.txt"
KEYWORD_LOADER = BASE_DIR / "keyword_loader.py"

UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'

# ── 카테고리·키워드 점수 (agent3/agent1 과 동일 로직) ──────────────────────────
CATEGORIES = {
    'SysML':    re.compile(r'SysML\s*v?2?|UML', re.I),
    'UAF':      re.compile(r'UAF|DoDAF|UPDM|NATO', re.I),
    'Tool':     re.compile(r'Cameo|Capella|Rhapsody|MagicDraw|software|tool', re.I),
    'Standard': re.compile(r'standard|ISO|IEEE|OMG|specification|INCOSE', re.I),
    'Research': re.compile(r'survey|framework|ontology|formal|method', re.I),
    'Digital':  re.compile(r'digital\s+engineering|digital\s+thread|digital\s+twin', re.I),
    'Industry': re.compile(r'industr|defense|aerospace|automotive|enterprise|mission', re.I),
}


def load_filter_and_scoring() -> tuple[str, dict, dict]:
    """keyword_loader 에서 filter 패턴과 scoring 가중치를 로드한다."""
    try:
        raw = subprocess.run(
            ['python3', str(KEYWORD_LOADER), '--format', 'filter', '--separator', '|'],
            capture_output=True, text=True, cwd=str(BASE_DIR)
        ).stdout.strip()
        pattern = raw or r'MBSE|SysML|model-based|systems engineering'
    except Exception:
        pattern = r'MBSE|SysML|model-based|systems engineering'
    try:
        raw = subprocess.run(
            ['python3', str(KEYWORD_LOADER), '--format', 'all'],
            capture_output=True, text=True, cwd=str(BASE_DIR)
        ).stdout
        d = json.loads(raw)
        core = {k: float(v) for k, v in d['scoring']['core'].items()}
        related = {k: float(v) for k, v in d['scoring']['related'].items()}
    except Exception:
        core = {'mbse': 10, 'model-based systems engineering': 10, 'sysml v2': 9, 'sysml': 8}
        related = {'systems engineering': 4, 'digital twin': 3, 'incose': 6, 'omg': 1}
    return pattern, core, related


FILTER_PATTERN, CORE_W, RELATED_W = load_filter_and_scoring()
KEYWORDS = re.compile(FILTER_PATTERN, re.I)


def categorize(text: str) -> str:
    for cat, pat in CATEGORIES.items():
        if pat.search(text):
            return cat
    return 'Research'


def keyword_score(text: str) -> int:
    text_l = text.lower()
    score = 0.0
    for term, w in CORE_W.items():
        score += len(re.findall(re.escape(term), text_l)) * w
    for term, w in RELATED_W.items():
        score += len(re.findall(re.escape(term), text_l)) * w
    return min(int(score), 20)


def load_cache() -> set:
    if CACHE_FILE.exists():
        with open(CACHE_FILE) as f:
            return set(f.read().splitlines())
    return set()


def fetch_url(url: str, retries: int = 3) -> str | None:
    """URL을 fetch하고 본문을 반환한다. 실패 시 None."""
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(
                url,
                headers={
                    'User-Agent': UA,
                    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                }
            )
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read().decode('utf-8', errors='replace')
        except Exception as e:
            print(f"  [fetch] 시도 {attempt}/{retries} 실패: {url[:80]} — {e}", flush=True)
            time.sleep(2 * attempt)
    return None


def fetch_rss_items(url: str) -> list:
    """Google News RSS 피드를 파싱해 [제목|링크|날짜] 목록을 반환한다."""
    xml = fetch_url(url)
    if not xml:
        return []
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as e:
        print(f"  [fetch_rss] 파싱 오류: {e}", flush=True)
        return []
    items = []
    for item in root.findall('.//item'):
        t = item.find('title')
        l = item.find('link')
        d = item.find('pubDate')
        title = re.sub(r'<[^>]+>', '', (t.text or '')).strip() if t is not None else ''
        # Google News 제목 끝 " - 언론사명" 제거
        title = re.sub(r'\s+-\s+[^-]{3,40}$', '', title).strip()
        link = (l.text or '').strip() if l is not None else ''
        date_raw = (d.text or '').strip() if d is not None else ''
        if title and link:
            items.append({'title': title, 'url': link, 'date_raw': date_raw})
    return items


def parse_rfc822(s: str):
    from email.utils import parsedate_to_datetime
    try:
        return parsedate_to_datetime(s)
    except Exception:
        return None


# ── OMG pressroom 전체 아카이브 ───────────────────────────────────────────────
OMG_RELEASE_PATTERN = re.compile(
    r'<a[^>]+href="([^"]*releases/pr(\d{4})/(\d{2})-(\d{2})-(\d{2})\.htm)"[^>]*>(.*?)</a>',
    re.DOTALL)


def fetch_omg_pressroom() -> list:
    """OMG pressroom 에서 보도자료 전체를 수집한다 (연도별 페이지 순회)."""
    items = []
    pressroom = fetch_url("https://www.omg.org/news/pressroom.htm")
    if not pressroom:
        print("[backfill-omg] pressroom 수집 실패", flush=True)
        return items

    seen = set()
    for href, year, month, day, yy, text in OMG_RELEASE_PATTERN.findall(pressroom):
        title = re.sub(r'<[^>]+>', '', text)
        title = re.sub(r'\s+', ' ', title).strip()
        if not href.startswith('http'):
            href = 'https://www.omg.org/' + href.lstrip('/')
        if href in seen:
            continue
        seen.add(href)
        date = f"{year}-{month}-{day}"
        items.append({'title': title, 'url': href, 'date_raw': date})
    return items


def month_range(start_date: str, end_date: str):
    """(년, 월) 범위 이터레이터."""
    sy, sm = int(start_date[:4]), int(start_date[5:7])
    ey, em = int(end_date[:4]), int(end_date[5:7])
    y, m = sy, sy and em  # placeholder, replaced below
    y, m = sy, sm
    while (y, m) <= (ey, em):
        yield y, m
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)


def main():
    import argparse
    parser = argparse.ArgumentParser(description="MBSE 뉴스 백필")
    parser.add_argument('--start', default='2026-06-10', help='수집 시작일 (YYYY-MM-DD)')
    parser.add_argument('--delay', type=float, default=2.0, help='요청 간 지연(초)')
    args = parser.parse_args()

    cache = load_cache()
    print(f"[backfill-news] 캐시 URL {len(cache)}건 제외", flush=True)

    # ── 1. Google News RSS: 키워드 쿼리 + site: 쿼리, 월별 기간 검색 ──────────────
    raw = subprocess.run(
        ['python3', str(KEYWORD_LOADER), '--format', 'google', '--limit', '8'],
        capture_output=True, text=True, cwd=str(BASE_DIR)
    ).stdout
    queries = [q.strip() for q in raw.splitlines() if q.strip()]

    # site: 쿼리도 포함 (INCOSE/OMG)
    site_queries = ['site:incose.org', 'site:omg.org']

    # 월별 기간: 시작일의 남은 일수부터 월 단위로
    today = datetime.now()
    start_dt = datetime.strptime(args.start, '%Y-%m-%d')

    all_results: dict[str, dict] = {}
    request_count = 0

    print(f"[backfill-news] Google News RSS 백필 — 키워드 {len(queries)}개 × 월별 기간", flush=True)

    # 쿼리 × 월 조합으로 검색 (Google News RSS after:/before: 연산자)
    # site: 쿼리도 포함 (INCOSE/OMG 공식 뉴스 우회 수집)
    months = list(month_range(start_dt, today))
    for q in queries + site_queries:
        for m_start, m_end in months:
            m_start_s = m_start.strftime('%Y-%m-%d')
            m_end_s = m_end.strftime('%Y-%m-%d')
            full_q = f'{q} after:{m_start_s} before:{m_end_s}'
            rss_url = f"https://news.google.com/rss/search?q={urllib.parse.quote_plus(full_q)}&hl=en-US&gl=US&ceid=US:en"
            try:
                items = fetch_rss_items(rss_url)
                request_count += 1
            except Exception as e:
                print(f"  RSS 실패: {q} ({m_start_s}) — {e}", flush=True)
                continue

            new_count = 0
            for it in items:
                url = it['url']
                if url in cache or url in all_results:
                    continue
                # site: 쿼리는 도메인 자체가 MBSE 관련이므로 키워드 필터 생략
                is_site_query = 'site:' in q
                if not is_site_query and not KEYWORDS.search(it['title']):
                    continue
                all_results[url] = {
                    'title': it['title'], 'url': url,
                    'date_raw': it['date_raw'],
                }
                new_count += 1
            time.sleep(args.delay)
        print(f"[backfill-news] '{q}' — 누적 {len(all_results)}건", flush=True)

    # ── 2. OMG pressroom 전체 아카이브 ──────────────────────────────────────────
    print(f"\n[backfill-news] OMG pressroom 아카이브 수집...", flush=True)
    omg_items = fetch_omg_pressroom()
    request_count += 1
    new_count = 0
    for it in omg_items:
        url = it['url']
        if url in all_results:
            continue
        all_results[url] = it
        new_count += 1
    print(f"  OMG 보도자료 {len(omg_items)}건 중 신규 {new_count}건 (누적 {len(all_results)})", flush=True)

    # ── 3. 날짜 파싱 + 정규화 + 월별 저장 ───────────────────────────────────────
    print(f"\n[backfill-news] 총 {len(all_results)}건 정규화 중...", flush=True)
    by_month: dict[str, list] = {}
    for it in all_results.values():
        dt = parse_date(it['date_raw'])
        if dt is None:
            continue
        month = dt.strftime('%Y-%m')
        title = it['title']
        text = title
        by_month.setdefault(month, []).append({
            'title': title,
            'url': it['url'],
            'date': dt.strftime('%Y-%m-%d'),
            'source': ('omg_press' if re.search(r'omg\.org/(news/)?releases/pr\d{4}', it['url'])
                       else ('incose_site' if 'incose.org' in it['url'] else 'news')),
            'category': categorize(text),
            'score': keyword_score(text),
            'summary': '',  # 백필은 AI 요약 없이 저장
        })

    os.makedirs(DATA_DIR, exist_ok=True)
    total = 0
    for month in sorted(by_month):
        items = sorted(by_month[month], key=lambda x: (x['date'], -x['score']))
        path = DATA_DIR / f"news-{month}.json"
        with open(path, 'w', encoding='utf-8') as f:
            json.dump({
                'type': 'news_archive',
                'month': month,
                'count': len(items),
                'items': items,
            }, f, ensure_ascii=False, indent=2)
        total += len(items)
        print(f"[backfill-news] {month}: {len(items)}건 → {path.name}", flush=True)

    index = {
        'type': 'news_index',
        'generated_at': datetime.now().strftime('%Y-%m-%dT%H:%M:%S'),
        'total': total,
        'months': {
            month: {'count': len(by_month[month]), 'file': f"news-{month}.json"}
            for month in sorted(by_month)
        },
    }
    with open(DATA_DIR / 'news-index.json', 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False, indent=2)

    print(f"\n[backfill-news] ══ 완료 — 총 {total}건, {len(by_month)}개월, 요청 {request_count}회 ══", flush=True)

    # ── 캐시 갱신 ─────────────────────────────────────────────────────────────
    if not dry_run_check():
        os.makedirs(CACHE_FILE.parent, exist_ok=True)
        with open(CACHE_FILE, 'a', encoding='utf-8') as f:
            for url in all_results:
                f.write(url + '\n')
        print(f"[backfill-news] 캐시 {len(all_results)}건 추가", flush=True)


def month_range(start: datetime, end: datetime):
    """월별 (월 시작일, 월 종료일) 쌍 이터레이터."""
    y, m = start.year, start.month
    while (y, m) <= (end.year, end.month):
        first = datetime(y, m, 1)
        if y == end.year and m == end.month:
            last = end
        else:
            # 다음 달 1일 - 1일 = 이번 달 말일
            ny, nm = (y + 1, 1) if m == 12 else (y, m + 1)
            last = datetime(ny, nm, 1) - timedelta(days=1)
        # 시작일이 월 중간이면 시작일부터
        actual_start = max(first, start)
        yield actual_start, last
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)


def parse_date(s: str):
    from email.utils import parsedate_to_datetime
    if not s:
        return None
    try:
        return parsedate_to_datetime(s).date()
    except Exception:
        pass
    try:
        return datetime.strptime(s[:10], '%Y-%m-%d').date()
    except Exception:
        return None


def dry_run_check() -> bool:
    return os.environ.get('DRY_RUN', '0') == '1'


if __name__ == '__main__':
    main()
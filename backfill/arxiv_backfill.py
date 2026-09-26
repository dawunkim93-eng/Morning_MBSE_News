#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────────
# 파일    : backfill/arxiv_backfill.py
# 설명    : arXiv MBSE 논문 전체 히스토리 백필 스크립트.
#           arXiv API의 제출일(submittedDate) 페이징 검색으로 MBSE 관련
#           논문을 전 기간에 걸쳐 수집한다.
#
#           출력: data/papers_archive/YYYY-MM.json (월별 파일)
#                 + data/_papers_index.json (전체 요약 인덱스)
#
# 사용법:
#   python3 backfill/arxiv_backfill.py [--start 2007-01] [--end 2026-09]
#                                       [--delay 4]
#
#   --start / --end : 수집 기간 (YYYY-MM). 기본값: 2007-01 ~ 이번 달
#                     (SysML 1.0 표준화가 시작된 2007년부터)
#   --delay         : arXiv API 요청 간 지연 초 (기본 3초, 예매 규정 준수)
#
# 주의:
#   - arXiv API 권장 지연은 요청당 3초. 백필은 요청 수가 많으므로 반드시 유지.
#   - 백필 항목은 AI 한국어 요약 없이 원문 초록(abstract)만 저장한다.
# ─────────────────────────────────────────────────────────────────────────────

import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
CACHE_FILE = BASE_DIR / "cache" / "seen_urls.txt"
KEYWORD_LOADER = BASE_DIR / "keyword_loader.py"

NS = {'atom': 'http://www.w3.org/2005/Atom'}

# ── 카테고리·키워드 점수 (agent3 와 동일 로직, 하드코딩 대신 플러그인 사용) ────
CATEGORIES = {
    'SysML':    re.compile(r'SysML\s*v?2?|UML', re.I),
    'UAF':      re.compile(r'UAF|DoDAF|UPDM|NATO', re.I),
    'Tool':     re.compile(r'Cameo|Capella|Rhapsody|MagicDraw|software|tool', re.I),
    'Standard': re.compile(r'standard|ISO|IEEE|OMG|specification|INCOSE', re.I),
    'Research': re.compile(r'survey|framework|ontology|formal|method', re.I),
    'Digital':  re.compile(r'digital\s+engineering|digital\s+thread|digital\s+twin', re.I),
    'Industry': re.compile(r'industr|defense|aerospace|automotive|enterprise|mission', re.I),
}


def load_scoring_weights() -> tuple[dict, dict]:
    """keyword_loader --format all 에서 scoring 가중치를 로드한다."""
    try:
        raw = os.popen(
            f"python3 '{KEYWORD_LOADER}' --format all"
        ).read()
        d = json.loads(raw)
        return (
            {k: float(v) for k, v in d['scoring']['core'].items()},
            {k: float(v) for k, v in d['scoring']['related'].items()},
        )
    except Exception as e:
        print(f"[backfill-arxiv] 가중치 로드 실패({e}) — 폴백 가중치 사용", flush=True)
        return (
            {'mbse': 10, 'model-based systems engineering': 10, 'sysml v2': 9, 'sysml': 8},
            {'systems engineering': 4, 'digital twin': 3, 'incose': 6, 'omg': 1},
        )


CORE_W, RELATED_W = load_scoring_weights()


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


def arxiv_search(query: str, start: int = 0, max_results: int = 100) -> bytes:
    """arXiv API 쿼리 실행 (이미 인코딩된 쿼리 문자열 사용)."""
    url = (
        "https://export.arxiv.org/api/query"
        f"?search_query={query}"
        f"&sortBy=submittedDate&sortOrder=descending"
        f"&start={start}&max_results={max_results}"
    )
    req = urllib.request.Request(
        url,
        headers={'User-Agent': 'MBSE-News-Bot/1.0 (backfill; contact via GitHub)'}
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def parse_feed(content: bytes) -> list:
    root = ET.fromstring(content)
    items = []
    for entry in root.findall('atom:entry', NS):
        t = entry.find('atom:title', NS)
        l = entry.find('atom:id', NS)
        p = entry.find('atom:published', NS)
        s = entry.find('atom:summary', NS)
        title = t.text.strip().replace('\n', ' ') if t is not None else ''
        url = l.text.strip() if l is not None else ''
        date = p.text[:10] if p is not None else ''
        abstract = s.text.strip().replace('\n', ' ') if s is not None else ''
        authors = ', '.join(
            a.find('atom:name', NS).text.strip()
            for a in entry.findall('atom:author', NS)
            if a.find('atom:name', NS) is not None
        )
        if title and url and date:
            text = f"{title} {abstract}"
            items.append({
                'title': title, 'url': url, 'date': date,
                'abstract': abstract, 'authors': authors,
                'source': 'arxiv', 'category': categorize(text),
                'score': keyword_score(text),
            })
    return items


def main():
    import argparse
    parser = argparse.ArgumentParser(description="arXiv MBSE 논문 백필")
    parser.add_argument('--start', default='2007-01', help='시작 년-월 (YYYY-MM)')
    parser.add_argument('--end', default=datetime.now().strftime('%Y-%m'), help='종료 년-월 (YYYY-MM)')
    parser.add_argument('--delay', type=float, default=3.0, help='API 요청 간 지연(초)')
    parser.add_argument('--batch', type=int, default=100, help='페이지당 결과 수 (arXiv 최대 100)')
    args = parser.parse_args()

    # 플러그인에서 arXiv 쿼리 로드 → ti:/abs: 구문 검색 OR 결합 (agent2 와 동일)
    raw = os.popen(f"python3 '{KEYWORD_LOADER}' --format arxiv").read()
    queries = [q.strip() for q in raw.splitlines() if q.strip()]
    parts = []
    for q in queries:
        enc = urllib.parse.quote_plus(f'"{q}"')
        parts.append(f'ti:{enc}')
        parts.append(f'abs:{enc}')
    base_query = '+OR+'.join(parts)
    print(f"[backfill-arxiv] 쿼리 {len(queries)}개 → 필드 검색 {len(parts)}건 결합", flush=True)

    cache = load_cache()
    print(f"[backfill-arxiv] 캐시 URL {len(cache)}건 제외", flush=True)

    # 연도별 그룹 검색: arXiv API는 submittedDate 범위 필터 지원
    # 전체 쿼리에 범위를 AND로 결합해 기간별로 수집 (페이징 용량 한계 회피)
    start_year = int(args.start[:4])
    start_month = int(args.start[5:7])
    end_year = int(args.end[:4])
    end_month = int(args.end[5:7])

    all_results: dict[str, dict] = {}  # url → item (중복 제거)
    request_count = 0

    # 월 단위(→ 연도 후반은 분기 단위) 범위로 검색해 100건/페이지 한계 회피
    y, m = start_year, start_month
    while (y, m) <= (end_year, end_month):
        # 기간: 1년 단위로 묶어 요청 수 절감 (단, 100건 초과 시 하위 분해)
        y_end, m_end = y, 12
        if (y, m_end) > (end_year, end_month):
            y_end, m_end = end_year, end_month
        range_start = f"{y}{m:02d}010000"
        range_end = f"{y_end}{m_end:02d}{['31','28','31','30','31','30','31','31','30','31','30','31'][m_end-1]}2359"
        range_q = f"+AND+submittedDate:[{range_start}+TO+{range_end}]"

        print(f"\n[backfill-arxiv] ══ {y}-{m:02d} ~ {y_end}-{m_end:02d} 검색 ══", flush=True)

        # 페이지네이션: 100건씩 반복, 빈 페이지 나올 때까지
        offset = 0
        while True:
            try:
                content = arxiv_search(base_query + range_q, start=offset, max_results=args.batch)
                request_count += 1
            except Exception as e:
                print(f"[backfill-arxiv] 요청 실패 (offset={offset}): {e}", flush=True)
                break

            items = parse_feed(content)
            if not items:
                break

            new_count = 0
            for item in items:
                url = item['url']
                if url in cache or url in all_results:
                    continue
                all_results[url] = item
                new_count += 1

            print(f"  offset={offset}: {len(items)}건 수집 (신규 {new_count}, 누적 {len(all_results)})", flush=True)

            # 마지막 페이지(부분 반환)면 종료
            if len(items) < args.batch:
                break
            offset += args.batch
            time.sleep(args.delay)

        time.sleep(args.delay)
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)

    # ── 월별 파일로 저장 ────────────────────────────────────────────────────────
    by_month: dict[str, list] = {}
    for item in all_results.values():
        month = item['date'][:7]
        by_month.setdefault(month, []).append(item)

    os.makedirs(DATA_DIR, exist_ok=True)
    total = 0
    for month in sorted(by_month):
        items = sorted(by_month[month], key=lambda x: (x['date'], -x['score']))
        path = DATA_DIR / f"papers-{month}.json"
        with open(path, 'w', encoding='utf-8') as f:
            json.dump({
                'type': 'papers_archive',
                'month': month,
                'count': len(items),
                'items': items,
            }, f, ensure_ascii=False, indent=2)
        total += len(items)
        print(f"[backfill-arxiv] {month}: {len(items)}건 → {path.name}", flush=True)

    # ── 인덱스 파일 ────────────────────────────────────────────────────────────
    index = {
        'type': 'papers_index',
        'generated_at': datetime.now().strftime('%Y-%m-%dT%H:%M:%S'),
        'total': total,
        'months': {
            month: {'count': len(by_month[month]),
                    'file': f"papers-{month}.json"}
            for month in sorted(by_month)
        },
    }
    with open(DATA_DIR / 'papers-index.json', 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False, indent=2)

    print(f"\n[backfill-arxiv] ══ 완료 — 총 {total}건, {len(by_month)}개월, "
          f"API 요청 {request_count}회 ══", flush=True)

    # ── 캐시 갱신 (신규 URL 추가) ───────────────────────────────────────────────
    if not dry_run_check():
        os.makedirs(CACHE_FILE.parent, exist_ok=True)
        with open(CACHE_FILE, 'a', encoding='utf-8') as f:
            for url in all_results:
                f.write(url + '\n')
        print(f"[backfill-arxiv] 캐시 {len(all_results)}건 추가", flush=True)


def dry_run_check() -> bool:
    return os.environ.get('DRY_RUN', '0') == '1'


if __name__ == '__main__':
    main()
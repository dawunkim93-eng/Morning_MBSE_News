# ─────────────────────────────────────────────────────────────────────────────
# 파일    : skills/arxiv.py
# 설명    : arXiv 논문 수집 스킬.
#           arXiv Atom API를 사용해 MBSE 관련 최신 프리프린트를 수집한다.
#           제출일 내림차순(최신순)으로 정렬된 결과를 반환한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — arXiv Atom API 파싱, 최신순 정렬 구현
# ─────────────────────────────────────────────────────────────────────────────

import requests
import xml.etree.ElementTree as ET
from config import HEADERS, ARXIV_QUERIES


def run(queries: list[str] = ARXIV_QUERIES, max_per_query: int = 3) -> list[dict]:
    """
    arXiv API로 MBSE 관련 최신 논문을 수집한다.

    쿼리별로 API를 요청하고 제목 기준 중복을 제거해 반환한다.

    매개변수:
        queries       : 검색 쿼리 목록 (기본값: config의 ARXIV_QUERIES)
        max_per_query : 쿼리당 최대 수집 개수 (기본값: 3)
    반환:
        {"title", "link", "date", "summary"} 형태의 딕셔너리 목록
    """
    seen, items = set(), []
    for query in queries:
        for p in _fetch(query, max_per_query):
            if p["title"] not in seen:
                seen.add(p["title"])
                items.append(p)
    return items


def _fetch(query: str, max_results: int = 3) -> list[dict]:
    """
    단일 쿼리로 arXiv Atom API를 요청하고 파싱한다.

    반환되는 Atom XML에서 <entry> 요소를 파싱해
    제목·링크·제출일·초록(summary)을 추출한다.

    매개변수:
        query       : arXiv API의 all: 필드에 전달할 검색어
        max_results : 최대 수집 개수
    반환:
        {"title", "link", "date", "summary"} 딕셔너리 목록 (요청 실패 시 빈 목록)
    """
    # sortBy=submittedDate: 제출일 최신순 정렬
    url = (
        "http://export.arxiv.org/api/query"
        f"?search_query=all:{requests.utils.quote(query)}"
        f"&sortBy=submittedDate&sortOrder=descending"
        f"&max_results={max_results}"
    )
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"  [arXiv:{query}] {e}")
        return []

    # arXiv는 Atom 형식 반환 → 네임스페이스 지정 필요
    ns = {"atom": "http://www.w3.org/2005/Atom"}
    try:
        root = ET.fromstring(resp.text)
    except ET.ParseError as e:
        print(f"  [arXiv] XML 파싱 오류: {e}")
        return []

    papers = []
    for entry in root.findall("atom:entry", ns):
        t = entry.find("atom:title",     ns)
        l = entry.find("atom:id",        ns)  # arXiv에서는 id가 논문 URL
        p = entry.find("atom:published", ns)
        s = entry.find("atom:summary",   ns)  # 논문 초록

        title   = t.text.strip().replace("\n", " ") if t is not None else ""
        link    = l.text.strip()               if l is not None else ""
        date    = p.text[:10]                  if p is not None else ""  # YYYY-MM-DD만 추출
        summary = s.text.strip().replace("\n", " ") if s is not None else ""

        if title and link:
            papers.append({"title": title, "link": link, "date": date, "summary": summary})

    return papers

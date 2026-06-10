# ─────────────────────────────────────────────────────────────────────────────
# 파일    : skills/semantic.py
# 설명    : Semantic Scholar 논문 수집 스킬.
#           Semantic Scholar Graph API를 사용해 MBSE 관련 논문을 수집한다.
#           arXiv와 달리 인용 수 정보가 포함되므로 영향력 있는 논문 필터링에 활용 가능하다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — Semantic Scholar API 파싱, 초록 포함 구현
# ─────────────────────────────────────────────────────────────────────────────

import requests
from config import HEADERS, SEMANTIC_SCHOLAR_QUERY


def run(query: str = SEMANTIC_SCHOLAR_QUERY, max_results: int = 5) -> list[dict]:
    """
    Semantic Scholar API로 MBSE 관련 논문을 수집한다.

    인증 없이 무료로 사용 가능하나 분당 요청 한도(100회)가 있다.
    fields 파라미터에 abstract를 포함해 초록도 함께 수집한다.

    매개변수:
        query       : 검색 쿼리 문자열 (기본값: config의 SEMANTIC_SCHOLAR_QUERY)
        max_results : 최대 수집 개수 (기본값: 5)
    반환:
        {"title", "link", "date", "summary"} 형태의 딕셔너리 목록
    """
    url = (
        "https://api.semanticscholar.org/graph/v1/paper/search"
        f"?query={requests.utils.quote(query)}"
        # 가져올 필드: 제목, URL, 출판연도, 초록
        f"&fields=title,url,year,abstract"
        f"&limit={max_results}"
    )
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        resp.raise_for_status()
        data = resp.json()
    except (requests.RequestException, ValueError) as e:
        print(f"  [Semantic Scholar] {e}")
        return []

    items = []
    for paper in data.get("data", []):
        title   = paper.get("title", "")
        link    = paper.get("url",   "")
        # year 필드는 정수이므로 문자열로 변환, 없으면 빈 문자열
        year    = str(paper.get("year", "")) if paper.get("year") else ""
        # 초록의 줄바꿈을 공백으로 정리
        summary = (paper.get("abstract") or "").replace("\n", " ")

        if title and link:
            items.append({"title": title, "link": link, "date": year, "summary": summary})

    return items

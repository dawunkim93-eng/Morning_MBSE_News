# ─────────────────────────────────────────────────────────────────────────────
# 파일    : skills/naver.py
# 설명    : 네이버 뉴스 검색 스킬.
#           네이버 뉴스 검색 결과 페이지를 HTML 파싱해 최신순 뉴스를 수집한다.
#           각 키워드에 대해 개별 요청을 보내고 중복을 제거해 반환한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — 네이버 뉴스 최신순 크롤링 구현
# ─────────────────────────────────────────────────────────────────────────────

import requests
from bs4 import BeautifulSoup
from config import HEADERS, NAVER_KEYWORDS


def run(keywords: list[str] = NAVER_KEYWORDS, max_per_keyword: int = 3) -> list[dict]:
    """
    네이버 뉴스 검색으로 MBSE 관련 뉴스를 수집한다.

    키워드별로 최신순(sort=1) 검색을 수행하고,
    여러 키워드에서 같은 기사가 나올 경우 중복을 제거한다.

    매개변수:
        keywords        : 검색에 사용할 키워드 목록 (기본값: config의 NAVER_KEYWORDS)
        max_per_keyword : 키워드당 최대 수집 개수 (기본값: 3)
    반환:
        {"title", "link", "summary"} 형태의 딕셔너리 목록
    """
    seen, items = set(), []
    for kw in keywords:
        for item in _fetch(kw, max_per_keyword):
            if item["title"] not in seen:
                seen.add(item["title"])
                items.append(item)
    return items


def _fetch(keyword: str, max_results: int = 3) -> list[dict]:
    """
    단일 키워드로 네이버 뉴스를 검색하고 결과를 반환한다.

    네이버 검색 결과 HTML에서 .news_area 블록을 파싱해
    제목(a.news_tit), 링크, 요약(.api_txt_lines 등)을 추출한다.

    매개변수:
        keyword     : 검색 키워드
        max_results : 최대 수집 개수
    반환:
        {"title", "link", "summary"} 딕셔너리 목록 (요청 실패 시 빈 목록)
    """
    # sort=1 : 최신순 정렬 (sort=0 이면 관련도순)
    url = (
        "https://search.naver.com/search.naver"
        f"?where=news&query={requests.utils.quote(keyword)}&sort=1"
    )
    try:
        resp = requests.get(url, headers=HEADERS, timeout=10)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"  [Naver:{keyword}] {e}")
        return []

    soup = BeautifulSoup(resp.text, "html.parser")
    results, seen = [], set()

    # 각 뉴스 블록(.news_area) 순회
    for area in soup.select(".news_area"):
        title_tag = area.select_one("a.news_tit")               # 뉴스 제목 링크
        desc_tag  = area.select_one(
            ".api_txt_lines, .dsc_txt_wrap, .news_dsc"          # 뉴스 요약 (selector 우선순위)
        )
        if not title_tag:
            continue

        title   = title_tag.get_text(strip=True)
        link    = title_tag.get("href", "")
        summary = desc_tag.get_text(strip=True) if desc_tag else ""

        if title and link and title not in seen:
            seen.add(title)
            results.append({"title": title, "link": link, "summary": summary})
        if len(results) >= max_results:
            break   # 목표 개수 달성 시 조기 종료

    return results

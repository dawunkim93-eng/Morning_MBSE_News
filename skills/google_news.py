# ─────────────────────────────────────────────────────────────────────────────
# 파일    : skills/google_news.py
# 설명    : Google News RSS 스킬.
#           Google News의 RSS 피드를 파싱해 MBSE 관련 영어 뉴스를 수집한다.
#           RSS <description> 태그에 HTML이 포함되므로 BeautifulSoup으로 제거한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — Google News RSS 파싱, HTML 스트리핑 구현
# ─────────────────────────────────────────────────────────────────────────────

import requests
import xml.etree.ElementTree as ET
from bs4 import BeautifulSoup
from config import HEADERS, GOOGLE_NEWS_QUERIES


def run(queries: list[str] = GOOGLE_NEWS_QUERIES, max_per_query: int = 5) -> list[dict]:
    """
    Google News RSS 피드로 MBSE 관련 뉴스를 수집한다.

    쿼리별로 RSS를 요청하고 중복을 제거해 반환한다.

    매개변수:
        queries       : 검색 쿼리 목록 (기본값: config의 GOOGLE_NEWS_QUERIES)
        max_per_query : 쿼리당 최대 수집 개수 (기본값: 5)
    반환:
        {"title", "link", "summary"} 형태의 딕셔너리 목록
    """
    seen, items = set(), []
    for query in queries:
        for item in _fetch(query, max_per_query):
            if item["title"] not in seen:
                seen.add(item["title"])
                items.append(item)
    return items


def _fetch(query: str, max_results: int = 5) -> list[dict]:
    """
    단일 쿼리로 Google News RSS를 요청하고 파싱한다.

    RSS XML에서 <item> 요소를 파싱해 제목·링크·요약을 추출한다.
    Google News 제목에 " - 출처명" 형태로 언론사 이름이 붙으므로 분리한다.
    <description>은 HTML을 포함할 수 있으므로 BeautifulSoup으로 텍스트만 추출한다.

    매개변수:
        query       : 검색 쿼리 문자열
        max_results : 최대 수집 개수
    반환:
        {"title", "link", "summary"} 딕셔너리 목록 (요청 실패 시 빈 목록)
    """
    # hl/gl/ceid 파라미터: 영어(미국) 결과로 고정
    url = (
        "https://news.google.com/rss/search"
        f"?q={requests.utils.quote(query)}&hl=en-US&gl=US&ceid=US:en"
    )
    try:
        resp = requests.get(url, headers=HEADERS, timeout=10)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"  [Google News:{query}] {e}")
        return []

    # RSS XML 파싱
    try:
        root = ET.fromstring(resp.text)
    except ET.ParseError as e:
        print(f"  [Google News] XML 파싱 오류: {e}")
        return []

    channel = root.find("channel")
    if channel is None:
        return []

    results = []
    for item in channel.findall("item")[:max_results]:
        title_el  = item.find("title")
        link_el   = item.find("link")
        guid_el   = item.find("guid")     # link가 없을 때 guid로 대체
        desc_el   = item.find("description")

        title = title_el.text.strip() if title_el is not None and title_el.text else ""
        # Google News 제목 끝의 " - 언론사명" 제거 (예: "MBSE Update - IEEE Spectrum" → "MBSE Update")
        title = title.rsplit(" - ", 1)[0].strip() if " - " in title else title

        # link 태그 우선, 없으면 guid 사용
        link = ""
        if link_el is not None and link_el.text:
            link = link_el.text.strip()
        elif guid_el is not None and guid_el.text:
            link = guid_el.text.strip()

        # description에 포함된 HTML 태그 제거
        summary = ""
        if desc_el is not None and desc_el.text:
            summary = BeautifulSoup(desc_el.text, "html.parser").get_text(strip=True)

        if title and link:
            results.append({"title": title, "link": link, "summary": summary})

    return results

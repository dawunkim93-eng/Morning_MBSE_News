# ─────────────────────────────────────────────────────────────────────────────
# 파일    : skills/incose.py
# 설명    : INCOSE(국제 시스템 엔지니어링 협회) 공식 홈페이지 뉴스 스킬.
#           INCOSE 뉴스 페이지를 HTML 파싱해 최신 공지/뉴스를 수집한다.
#           사이트 CMS 구조가 바뀔 수 있으므로 여러 CSS selector를 순차 시도한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — INCOSE 뉴스 다중 selector 폴백 파싱 구현
# ─────────────────────────────────────────────────────────────────────────────

import requests
from bs4 import BeautifulSoup
from config import HEADERS

# INCOSE 사이트 CMS 구조에 따라 다를 수 있는 CSS selector 목록
# 앞쪽 selector가 결과를 반환하면 이후 selector는 시도하지 않음 (폴백 체인)
_SELECTORS = [
    ("h3.news-heading a",    ".news-summary, .news-description, p"),
    ("h2.news-title a",      ".news-summary, p"),
    (".news-list-item a",    "p"),
    ("article h3 a",         "p"),
    ("article h2 a",         "p"),
]


def run(max_results: int = 5) -> list[dict]:
    """
    INCOSE 뉴스 페이지에서 최신 뉴스를 수집한다.

    사이트가 JavaScript 렌더링을 사용하는 경우 결과가 0건일 수 있으며,
    이 경우 Selenium 기반 크롤러로 교체가 필요하다.

    매개변수:
        max_results : 수집할 최대 뉴스 건수 (기본값: 5)
    반환:
        {"title", "link", "summary"} 형태의 딕셔너리 목록
    """
    url = "https://www.incose.org/news-and-events/news"
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"  [INCOSE] {e}")
        return []

    soup  = BeautifulSoup(resp.text, "html.parser")
    items, seen = [], set()

    # selector 폴백 체인: 결과가 나오는 첫 번째 selector 사용
    for title_sel, desc_sel in _SELECTORS:
        tags = soup.select(title_sel)
        if not tags:
            continue  # 이 selector로는 결과 없음 → 다음 selector 시도

        for tag in tags[:max_results]:
            title = tag.get_text(strip=True)
            href  = tag.get("href", "")
            # 상대 경로(예: /news/article-123)를 절대 URL로 변환
            if href and not href.startswith("http"):
                href = "https://www.incose.org" + href

            # 제목 태그의 부모 컨테이너에서 설명 텍스트 추출
            summary = ""
            parent = tag.find_parent(["article", "li", "div"])
            if parent:
                desc_tag = parent.select_one(desc_sel)
                if desc_tag:
                    summary = desc_tag.get_text(strip=True)

            if title and href and title not in seen:
                seen.add(title)
                items.append({"title": title, "link": href, "summary": summary})

        break  # 결과가 있었으므로 폴백 체인 중단

    return items

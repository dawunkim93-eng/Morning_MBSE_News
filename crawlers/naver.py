import requests
from bs4 import BeautifulSoup
from config import HEADERS, NAVER_KEYWORDS


def _fetch_naver(keyword: str, max_results: int = 3) -> list[dict]:
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

    for area in soup.select(".news_area"):
        title_tag = area.select_one("a.news_tit")
        desc_tag = area.select_one(".api_txt_lines, .dsc_txt_wrap, .news_dsc")
        if not title_tag:
            continue
        title = title_tag.get_text(strip=True)
        link = title_tag.get("href", "")
        summary = desc_tag.get_text(strip=True) if desc_tag else ""
        if title and link and title not in seen:
            seen.add(title)
            results.append({"title": title, "link": link, "summary": summary})
        if len(results) >= max_results:
            break
    return results


def collect_naver_news() -> list[dict]:
    seen, items = set(), []
    for kw in NAVER_KEYWORDS:
        for item in _fetch_naver(kw):
            if item["title"] not in seen:
                seen.add(item["title"])
                items.append(item)
    return items

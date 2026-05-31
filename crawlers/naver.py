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
    for tag in soup.select("a.news_tit"):
        title = tag.get_text(strip=True)
        link = tag.get("href", "")
        if title and link and title not in seen:
            seen.add(title)
            results.append({"title": title, "link": link})
        if len(results) >= max_results:
            break
    return results


def collect_naver_news() -> list[str]:
    seen, lines = set(), []
    for kw in NAVER_KEYWORDS:
        for item in _fetch_naver(kw):
            if item["title"] not in seen:
                seen.add(item["title"])
                lines.append(f"📰 {item['title']}\n{item['link']}")
    return lines

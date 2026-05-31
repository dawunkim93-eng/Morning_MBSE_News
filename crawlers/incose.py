import requests
from bs4 import BeautifulSoup
from config import HEADERS

_SELECTORS = [
    "h3.news-heading a",
    "h2.news-title a",
    ".news-list-item a",
    ".article-title a",
    "article h3 a",
    "article h2 a",
    ".sf-content-block h3 a",
    "li.news-item a",
]


def collect_incose_news(max_results: int = 5) -> list[str]:
    url = "https://www.incose.org/news-and-events/news"
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"  [INCOSE] {e}")
        return []

    soup = BeautifulSoup(resp.text, "html.parser")
    lines, seen = [], set()

    for selector in _SELECTORS:
        tags = soup.select(selector)
        if not tags:
            continue
        for tag in tags[:max_results]:
            title = tag.get_text(strip=True)
            href = tag.get("href", "")
            if href and not href.startswith("http"):
                href = "https://www.incose.org" + href
            if title and href and title not in seen:
                seen.add(title)
                lines.append(f"🏛 {title}\n{href}")
        break

    return lines

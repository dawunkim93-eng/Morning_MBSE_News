import requests
from bs4 import BeautifulSoup
from config import HEADERS

_SELECTORS = [
    ("h3.news-heading a", ".news-summary, .news-description, p"),
    ("h2.news-title a", ".news-summary, p"),
    (".news-list-item a", "p"),
    ("article h3 a", "p"),
    ("article h2 a", "p"),
]


def collect_incose_news(max_results: int = 5) -> list[dict]:
    url = "https://www.incose.org/news-and-events/news"
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"  [INCOSE] {e}")
        return []

    soup = BeautifulSoup(resp.text, "html.parser")
    items, seen = [], set()

    for title_sel, desc_sel in _SELECTORS:
        tags = soup.select(title_sel)
        if not tags:
            continue
        for tag in tags[:max_results]:
            title = tag.get_text(strip=True)
            href = tag.get("href", "")
            if href and not href.startswith("http"):
                href = "https://www.incose.org" + href

            summary = ""
            parent = tag.find_parent(["article", "li", "div"])
            if parent:
                desc_tag = parent.select_one(desc_sel)
                if desc_tag:
                    summary = desc_tag.get_text(strip=True)

            if title and href and title not in seen:
                seen.add(title)
                items.append({"title": title, "link": href, "summary": summary})
        break

    return items

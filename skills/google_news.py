import requests
import xml.etree.ElementTree as ET
from bs4 import BeautifulSoup
from config import HEADERS, GOOGLE_NEWS_QUERIES


def run(queries: list[str] = GOOGLE_NEWS_QUERIES, max_per_query: int = 5) -> list[dict]:
    seen, items = set(), []
    for query in queries:
        for item in _fetch(query, max_per_query):
            if item["title"] not in seen:
                seen.add(item["title"])
                items.append(item)
    return items


def _fetch(query: str, max_results: int = 5) -> list[dict]:
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

    try:
        root = ET.fromstring(resp.text)
    except ET.ParseError as e:
        print(f"  [Google News] XML parse error: {e}")
        return []

    channel = root.find("channel")
    if channel is None:
        return []

    results = []
    for item in channel.findall("item")[:max_results]:
        title_el = item.find("title")
        link_el = item.find("link")
        guid_el = item.find("guid")
        desc_el = item.find("description")

        title = title_el.text.strip() if title_el is not None and title_el.text else ""
        title = title.rsplit(" - ", 1)[0].strip() if " - " in title else title
        link = ""
        if link_el is not None and link_el.text:
            link = link_el.text.strip()
        elif guid_el is not None and guid_el.text:
            link = guid_el.text.strip()
        summary = ""
        if desc_el is not None and desc_el.text:
            summary = BeautifulSoup(desc_el.text, "html.parser").get_text(strip=True)

        if title and link:
            results.append({"title": title, "link": link, "summary": summary})
    return results

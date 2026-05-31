import requests
import xml.etree.ElementTree as ET
from config import HEADERS, GOOGLE_NEWS_QUERIES


def _fetch_google_rss(query: str, max_results: int = 5) -> list[dict]:
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
        source_el = item.find("source")

        title = title_el.text.strip() if title_el is not None and title_el.text else ""
        link = ""
        if link_el is not None and link_el.text:
            link = link_el.text.strip()
        elif guid_el is not None and guid_el.text:
            link = guid_el.text.strip()
        source = source_el.text.strip() if source_el is not None and source_el.text else ""

        if title and link:
            results.append({"title": title, "link": link, "source": source})
    return results


def collect_google_news() -> list[str]:
    seen, lines = set(), []
    for query in GOOGLE_NEWS_QUERIES:
        for item in _fetch_google_rss(query):
            if item["title"] not in seen:
                seen.add(item["title"])
                src = f"  [{item['source']}]" if item["source"] else ""
                lines.append(f"📰 {item['title']}{src}\n{item['link']}")
    return lines

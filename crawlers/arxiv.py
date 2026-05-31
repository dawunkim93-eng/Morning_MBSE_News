import requests
import xml.etree.ElementTree as ET
from config import HEADERS, ARXIV_QUERIES


def _fetch_arxiv(query: str, max_results: int = 3) -> list[dict]:
    url = (
        "http://export.arxiv.org/api/query"
        f"?search_query=all:{requests.utils.quote(query)}"
        f"&sortBy=submittedDate&sortOrder=descending"
        f"&max_results={max_results}"
    )
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"  [arXiv:{query}] {e}")
        return []

    ns = {"atom": "http://www.w3.org/2005/Atom"}
    try:
        root = ET.fromstring(resp.text)
    except ET.ParseError as e:
        print(f"  [arXiv] XML parse error: {e}")
        return []

    papers = []
    for entry in root.findall("atom:entry", ns):
        t = entry.find("atom:title", ns)
        l = entry.find("atom:id", ns)
        p = entry.find("atom:published", ns)
        title = t.text.strip().replace("\n", " ") if t is not None else ""
        link = l.text.strip() if l is not None else ""
        published = p.text[:10] if p is not None else ""
        if title and link:
            papers.append({"title": title, "link": link, "published": published})
    return papers


def collect_arxiv_papers() -> list[str]:
    seen, lines = set(), []
    for query in ARXIV_QUERIES:
        for p in _fetch_arxiv(query):
            if p["title"] not in seen:
                seen.add(p["title"])
                lines.append(f"📄 {p['title']}\n   🗓 {p['published']}  |  {p['link']}")
    return lines

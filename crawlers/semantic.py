import requests
from config import HEADERS, SEMANTIC_SCHOLAR_QUERY


def collect_semantic_scholar(max_results: int = 5) -> list[dict]:
    url = (
        "https://api.semanticscholar.org/graph/v1/paper/search"
        f"?query={requests.utils.quote(SEMANTIC_SCHOLAR_QUERY)}"
        f"&fields=title,url,year,abstract"
        f"&limit={max_results}"
    )
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        resp.raise_for_status()
        data = resp.json()
    except (requests.RequestException, ValueError) as e:
        print(f"  [Semantic Scholar] {e}")
        return []

    items = []
    for paper in data.get("data", []):
        title = paper.get("title", "")
        link = paper.get("url", "")
        year = str(paper.get("year", "")) if paper.get("year") else ""
        summary = (paper.get("abstract") or "").replace("\n", " ")
        if title and link:
            items.append({"title": title, "link": link, "date": year, "summary": summary})
    return items

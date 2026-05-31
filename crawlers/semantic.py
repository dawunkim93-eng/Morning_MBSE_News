import requests
from config import HEADERS, SEMANTIC_SCHOLAR_QUERY


def collect_semantic_scholar(max_results: int = 5) -> list[str]:
    url = (
        "https://api.semanticscholar.org/graph/v1/paper/search"
        f"?query={requests.utils.quote(SEMANTIC_SCHOLAR_QUERY)}"
        f"&fields=title,url,year,authors"
        f"&limit={max_results}"
    )
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        resp.raise_for_status()
        data = resp.json()
    except (requests.RequestException, ValueError) as e:
        print(f"  [Semantic Scholar] {e}")
        return []

    lines = []
    for paper in data.get("data", []):
        title = paper.get("title", "")
        link = paper.get("url", "")
        year = paper.get("year", "")
        if title and link:
            lines.append(f"📄 {title}\n   🗓 {year}  |  {link}")
    return lines

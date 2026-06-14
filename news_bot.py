import requests
import xml.etree.ElementTree as ET
from bs4 import BeautifulSoup
from datetime import datetime, timezone, timedelta

TELEGRAM_TOKEN = "8912263711:AAEpHvyFKL3uz_kAXYk8pBzV-bQBhIkX2bg"
CHAT_ID = "5274268176"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    )
}
KST = timezone(timedelta(hours=9))

# ── 키워드 설정 ────────────────────────────────────
NAVER_KEYWORDS = [
    "MBSE",
    "Model-Based Systems Engineering",
    "SysML",
    "시스템 엔지니어링",
    "MOSA",
]

GOOGLE_NEWS_QUERIES = [
    "MBSE systems engineering",
    "Model-Based Systems Engineering",
    "SysML modeling",
]

ARXIV_QUERIES = [
    "Model-Based Systems Engineering",
    "SysML MBSE",
    "MBSE digital twin",
]

SEMANTIC_SCHOLAR_QUERY = "Model-Based Systems Engineering MBSE SysML"


# ════════════════════════════════════════════
# 뉴스 크롤링
# ════════════════════════════════════════════

# ── 1. 네이버 뉴스 ─────────────────────────
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


# ── 2. Google News RSS ─────────────────────
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
        # link 태그가 None 텍스트면 guid 사용
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


# ── 3. INCOSE (SE 국제 학회) ───────────────
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

    # INCOSE CMS 구조에 따라 여러 selector 순차 시도
    for selector in [
        "h3.news-heading a",
        "h2.news-title a",
        ".news-list-item a",
        ".article-title a",
        "article h3 a",
        "article h2 a",
        ".sf-content-block h3 a",
        "li.news-item a",
    ]:
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
        break  # 첫 번째로 결과가 나온 selector 사용

    return lines


# ════════════════════════════════════════════
# 논문 크롤링
# ════════════════════════════════════════════

# ── 4. arXiv API ──────────────────────────
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


# ── 5. Semantic Scholar API ────────────────
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


# ════════════════════════════════════════════
# 텔레그램 전송
# ════════════════════════════════════════════

def send_telegram(message: str) -> None:
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    for chunk in [message[i:i + 4000] for i in range(0, len(message), 4000)]:
        try:
            resp = requests.post(
                url, data={"chat_id": CHAT_ID, "text": chunk}, timeout=10
            )
            resp.raise_for_status()
        except requests.RequestException as e:
            print(f"  텔레그램 전송 실패: {e}")


# ════════════════════════════════════════════
# 메인
# ════════════════════════════════════════════

if __name__ == "__main__":
    today = datetime.now(KST).strftime("%Y년 %m월 %d일 (%a)")
    print(f"크롤링 시작: {today}")

    # ── 뉴스 수집 ──────────────────────────
    print("[1/5] 네이버 뉴스...")
    naver = collect_naver_news()

    print("[2/5] Google News RSS...")
    google = collect_google_news()

    print("[3/5] INCOSE...")
    incose = collect_incose_news()

    # ── 논문 수집 ──────────────────────────
    print("[4/5] arXiv...")
    arxiv = collect_arxiv_papers()

    print("[5/5] Semantic Scholar...")
    semantic = collect_semantic_scholar()

    # ── 메시지 조립 ────────────────────────
    sep = "\n" + "─" * 28
    sections = [f"🛰 MBSE 데일리 브리핑  |  {today}\n{'━' * 32}"]

    sections += [f"\n📡 뉴스 — 네이버{sep}"] + (naver or ["관련 뉴스 없음"])
    sections += [f"\n📡 뉴스 — Google News{sep}"] + (google or ["관련 뉴스 없음"])
    sections += [f"\n🏛 뉴스 — INCOSE{sep}"] + (incose or ["관련 뉴스 없음"])
    sections += [f"\n🔬 논문 — arXiv{sep}"] + (arxiv or ["관련 논문 없음"])
    sections += [f"\n🔬 논문 — Semantic Scholar{sep}"] + (semantic or ["관련 논문 없음"])

    send_telegram("\n\n".join(sections))

    print("\n전송 완료")
    print(f"  네이버    {len(naver):2d}건")
    print(f"  Google    {len(google):2d}건")
    print(f"  INCOSE    {len(incose):2d}건")
    print(f"  arXiv     {len(arxiv):2d}건")
    print(f"  Semantic  {len(semantic):2d}건")

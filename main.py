from datetime import datetime
from config import KST
from crawlers import (
    collect_naver_news,
    collect_google_news,
    collect_incose_news,
    collect_arxiv_papers,
    collect_semantic_scholar,
)
from notifier import send_telegram
from utils import translate_to_korean, smart_truncate


def _format_news(item: dict) -> str:
    lines = [f"📰 {item['title']}"]
    if item.get("summary"):
        summary = smart_truncate(translate_to_korean(item["summary"]), max_sentences=2)
        lines.append(f"💬 {summary}")
    lines.append(item["link"])
    return "\n".join(lines)


def _format_paper(item: dict) -> str:
    lines = [f"📄 {item['title']}"]
    if item.get("summary"):
        summary = smart_truncate(translate_to_korean(item["summary"]), max_sentences=3)
        lines.append(f"💬 {summary}")
    date_str = f"🗓 {item['date']}  |  " if item.get("date") else ""
    lines.append(f"{date_str}{item['link']}")
    return "\n".join(lines)


def _dedup(items: list[dict]) -> list[dict]:
    seen, result = set(), []
    for item in items:
        if item["title"] not in seen:
            seen.add(item["title"])
            result.append(item)
    return result


def build_message(today: str) -> str:
    SEP = "\n" + "─" * 28
    sections = [f"🛰 MBSE 데일리 브리핑  |  {today}\n{'━' * 32}"]

    # ── 뉴스 ──────────────────────────────────
    print("[1/5] 네이버 뉴스...")
    naver = collect_naver_news()

    print("[2/5] Google News...")
    google = collect_google_news()

    print("[3/5] INCOSE...")
    incose = collect_incose_news()

    news_items = _dedup(naver + google + incose)
    print(f"      번역 중 ({len(news_items)}건)...")
    news_lines = [_format_news(i) for i in news_items]
    sections += [f"\n📡 뉴스{SEP}"] + (news_lines or ["관련 뉴스 없음"])

    # ── 논문 ──────────────────────────────────
    print("[4/5] arXiv...")
    arxiv = collect_arxiv_papers()

    print("[5/5] Semantic Scholar...")
    semantic = collect_semantic_scholar()

    paper_items = _dedup(arxiv + semantic)
    print(f"      번역 중 ({len(paper_items)}건)...")
    paper_lines = [_format_paper(i) for i in paper_items]
    sections += [f"\n🔬 논문{SEP}"] + (paper_lines or ["관련 논문 없음"])

    print(f"\n수집 완료 | 뉴스 {len(news_lines)}건 / 논문 {len(paper_lines)}건")
    return "\n\n".join(sections)


if __name__ == "__main__":
    today = datetime.now(KST).strftime("%Y년 %m월 %d일 (%a)")
    print(f"크롤링 시작: {today}\n")
    message = build_message(today)
    send_telegram(message)
    print("텔레그램 전송 완료")

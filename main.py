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

SEP = "\n" + "─" * 28


def build_message(today: str) -> str:
    sections = [f"🛰 MBSE 데일리 브리핑  |  {today}\n{'━' * 32}"]

    print("[1/5] 네이버 뉴스...")
    naver = collect_naver_news()
    sections += [f"\n📡 뉴스 — 네이버{SEP}"] + (naver or ["관련 뉴스 없음"])

    print("[2/5] Google News RSS...")
    google = collect_google_news()
    sections += [f"\n📡 뉴스 — Google News{SEP}"] + (google or ["관련 뉴스 없음"])

    print("[3/5] INCOSE...")
    incose = collect_incose_news()
    sections += [f"\n🏛 뉴스 — INCOSE{SEP}"] + (incose or ["관련 뉴스 없음"])

    print("[4/5] arXiv...")
    arxiv = collect_arxiv_papers()
    sections += [f"\n🔬 논문 — arXiv{SEP}"] + (arxiv or ["관련 논문 없음"])

    print("[5/5] Semantic Scholar...")
    semantic = collect_semantic_scholar()
    sections += [f"\n🔬 논문 — Semantic Scholar{SEP}"] + (semantic or ["관련 논문 없음"])

    print(
        f"\n수집 완료 | 네이버 {len(naver)}건 / Google {len(google)}건 / "
        f"INCOSE {len(incose)}건 / arXiv {len(arxiv)}건 / Semantic {len(semantic)}건"
    )
    return "\n\n".join(sections)


if __name__ == "__main__":
    today = datetime.now(KST).strftime("%Y년 %m월 %d일 (%a)")
    print(f"크롤링 시작: {today}\n")
    message = build_message(today)
    send_telegram(message)
    print("텔레그램 전송 완료")

import html as _html
from skills.translate import translate, smart_truncate
from notifier import send_telegram

_e = _html.escape


class NotifierAgent:
    """번역·포맷·전송 에이전트 — translate / send_telegram 스킬 사용."""

    def _format_news(self, item: dict) -> str:
        title = _e(item["title"])
        lines = [f"📰 <b>{title}</b>"]
        if item.get("summary"):
            lines.append(f"💬 {_e(translate(item['summary']))}")
        lines.append(f'<a href="{_e(item["link"])}">🔗 기사 보기</a>')
        return "\n".join(lines)

    def _format_paper(self, item: dict) -> str:
        title = _e(item["title"])
        lines = [f"📄 <b>{title}</b>"]
        if item.get("summary"):
            summary = _e(smart_truncate(translate(item["summary"]), max_sentences=3))
            lines.append(f"💬 {summary}")
        date_str = f"🗓 {item['date']}  |  " if item.get("date") else ""
        lines.append(f"{date_str}<a href=\"{_e(item['link'])}\">🔗 논문 보기</a>")
        return "\n".join(lines)

    def send(self, news: list[dict], papers: list[dict], today: str) -> None:
        SEP = "\n" + "─" * 28
        sections = [f"🛰 MBSE 데일리 브리핑  |  {today}\n{'━' * 32}"]

        news_lines = [self._format_news(i) for i in news]
        sections += [f"\n📡 뉴스{SEP}"] + (news_lines or ["관련 뉴스 없음"])

        paper_lines = [self._format_paper(i) for i in papers]
        sections += [f"\n🔬 논문{SEP}"] + (paper_lines or ["관련 논문 없음"])

        print(f"  [NotifierAgent] 뉴스 {len(news_lines)}건 / 논문 {len(paper_lines)}건 전송")
        send_telegram("\n\n".join(sections))

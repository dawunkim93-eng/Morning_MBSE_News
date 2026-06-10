# ─────────────────────────────────────────────────────────────────────────────
# 파일    : agents/notifier_agent.py
# 설명    : 번역·포맷·전송 에이전트.
#           뉴스/논문 아이템을 HTML 형식으로 변환하고
#           텔레그램으로 발송하는 역할을 담당한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — HTML 포맷 변환, 번역, 텔레그램 전송 구현
# ─────────────────────────────────────────────────────────────────────────────

import html as _html

from skills.translate import translate, smart_truncate
from notifier import send_telegram

# HTML 특수문자 이스케이프 함수 단축 참조
# 텔레그램 HTML 모드에서 &, <, >, " 등을 안전하게 처리하기 위해 반드시 사용
_e = _html.escape


class NotifierAgent:
    """
    번역·포맷·전송 에이전트.

    translate 스킬로 요약문을 한국어로 번역하고,
    HTML 형식으로 가공한 뒤 send_telegram 스킬로 전송한다.
    """

    def _format_news(self, item: dict) -> str:
        """
        뉴스 아이템 하나를 텔레그램 HTML 메시지 블록으로 변환한다.

        출력 형식:
            📰 <b>제목</b>
            💬 한국어 요약
            🔗 기사 보기 (링크)
        """
        title = _e(item["title"])                         # 제목의 HTML 특수문자 이스케이프
        lines = [f"📰 <b>{title}</b>"]                    # 제목 굵게 표시

        if item.get("summary"):
            # 요약문을 한국어로 번역 후 HTML 이스케이프 처리
            lines.append(f"💬 {_e(translate(item['summary']))}")

        # URL의 & 등 특수문자도 이스케이프해야 href 파싱 오류를 방지
        lines.append(f'<a href="{_e(item["link"])}">🔗 기사 보기</a>')
        return "\n".join(lines)

    def _format_paper(self, item: dict) -> str:
        """
        논문 아이템 하나를 텔레그램 HTML 메시지 블록으로 변환한다.

        논문 초록은 길기 때문에 3문장으로 제한한다.

        출력 형식:
            📄 <b>제목</b>
            💬 한국어 요약 (3문장)
            🗓 출판연도  |  🔗 논문 보기 (링크)
        """
        title = _e(item["title"])
        lines = [f"📄 <b>{title}</b>"]

        if item.get("summary"):
            # 초록 번역 후 3문장으로 제한 (너무 길면 메시지가 복잡해짐)
            summary = _e(smart_truncate(translate(item["summary"]), max_sentences=3))
            lines.append(f"💬 {summary}")

        # 발행 연도가 있으면 링크 앞에 표시
        date_str = f"🗓 {item['date']}  |  " if item.get("date") else ""
        lines.append(f"{date_str}<a href=\"{_e(item['link'])}\">🔗 논문 보기</a>")
        return "\n".join(lines)

    def send(self, news: list[dict], papers: list[dict], today: str) -> None:
        """
        뉴스와 논문 목록을 하나의 텔레그램 메시지로 조합해 전송한다.

        매개변수:
            news   : 뉴스 아이템 목록 (NewsAgent.run() 결과)
            papers : 논문 아이템 목록 (PaperAgent.run() 결과)
            today  : 메시지 헤더에 표시할 날짜 문자열
        """
        SEP = "\n" + "─" * 28  # 섹션 구분선

        # 메시지 헤더
        sections = [f"🛰 MBSE 데일리 브리핑  |  {today}\n{'━' * 32}"]

        # 뉴스 섹션 구성
        news_lines = [self._format_news(i) for i in news]
        sections += [f"\n📡 뉴스{SEP}"] + (news_lines or ["관련 뉴스 없음"])

        # 논문 섹션 구성
        paper_lines = [self._format_paper(i) for i in papers]
        sections += [f"\n🔬 논문{SEP}"] + (paper_lines or ["관련 논문 없음"])

        print(f"  [NotifierAgent] 뉴스 {len(news_lines)}건 / 논문 {len(paper_lines)}건 전송")
        # 섹션들을 빈 줄로 구분해 하나의 메시지로 합쳐 전송
        send_telegram("\n\n".join(sections))

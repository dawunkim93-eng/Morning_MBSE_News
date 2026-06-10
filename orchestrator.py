from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from config import KST
from agents import NewsAgent, PaperAgent, NotifierAgent


class Orchestrator:
    """
    NewsAgent / PaperAgent 를 병렬 실행하고
    NotifierAgent 로 결과를 통합·발송하는 최상위 조율자.
    """

    def __init__(self) -> None:
        self.news_agent = NewsAgent()
        self.paper_agent = PaperAgent()
        self.notifier = NotifierAgent()

    def run(self) -> None:
        today = datetime.now(KST).strftime("%Y년 %m월 %d일 (%a)")
        print(f"[Orchestrator] 시작: {today}")

        # NewsAgent 와 PaperAgent 병렬 실행
        with ThreadPoolExecutor(max_workers=2) as pool:
            news_f = pool.submit(self.news_agent.run)
            paper_f = pool.submit(self.paper_agent.run)
            news = news_f.result()
            papers = paper_f.result()

        print(f"[Orchestrator] 수집 완료 — 뉴스 {len(news)}건 / 논문 {len(papers)}건")
        self.notifier.send(news, papers, today)
        print("[Orchestrator] 발송 완료")

from concurrent.futures import ThreadPoolExecutor, as_completed
from agents.base import BaseAgent
from skills import naver, google_news, incose
from utils import score_mbse_relevance


class NewsAgent(BaseAgent):
    """뉴스 수집 에이전트 — naver / google_news / incose 스킬을 병렬 실행."""

    _SKILLS = [
        ("naver",       naver.run),
        ("google_news", google_news.run),
        ("incose",      incose.run),
    ]

    def run(self) -> list[dict]:
        all_items: list[dict] = []

        with ThreadPoolExecutor(max_workers=len(self._SKILLS)) as pool:
            futures = {pool.submit(fn): name for name, fn in self._SKILLS}
            for future in as_completed(futures):
                name = futures[future]
                try:
                    all_items.extend(future.result())
                    print(f"  [NewsAgent] {name} 완료")
                except Exception as e:
                    print(f"  [NewsAgent] {name} 실패: {e}")

        return sorted(self._dedup(all_items), key=score_mbse_relevance, reverse=True)

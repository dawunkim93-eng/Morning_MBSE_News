from concurrent.futures import ThreadPoolExecutor, as_completed
from agents.base import BaseAgent
from skills import arxiv, semantic
from utils import score_mbse_relevance


class PaperAgent(BaseAgent):
    """논문 수집 에이전트 — arxiv / semantic 스킬을 병렬 실행."""

    _SKILLS = [
        ("arxiv",    arxiv.run),
        ("semantic", semantic.run),
    ]

    def run(self) -> list[dict]:
        all_items: list[dict] = []

        with ThreadPoolExecutor(max_workers=len(self._SKILLS)) as pool:
            futures = {pool.submit(fn): name for name, fn in self._SKILLS}
            for future in as_completed(futures):
                name = futures[future]
                try:
                    all_items.extend(future.result())
                    print(f"  [PaperAgent] {name} 완료")
                except Exception as e:
                    print(f"  [PaperAgent] {name} 실패: {e}")

        return sorted(self._dedup(all_items), key=score_mbse_relevance, reverse=True)

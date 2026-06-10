# ─────────────────────────────────────────────────────────────────────────────
# 파일    : agents/paper_agent.py
# 설명    : 논문 수집 에이전트. arXiv API와 Semantic Scholar API 두 스킬을
#           ThreadPoolExecutor 로 동시에 실행해 전체 대기 시간을 단축한다.
#           수집 후 중복 제거 및 MBSE 관련도 점수 내림차순 정렬을 수행한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — 병렬 논문 수집 에이전트 구현
# ─────────────────────────────────────────────────────────────────────────────

from concurrent.futures import ThreadPoolExecutor, as_completed

from agents.base import BaseAgent
from skills import arxiv, semantic
from utils import score_mbse_relevance


class PaperAgent(BaseAgent):
    """
    논문 수집 에이전트.

    arxiv / semantic 스킬을 병렬로 호출해 논문을 수집하고
    MBSE 관련도 높은 순으로 정렬해 반환한다.
    """

    # 실행할 스킬 목록: (이름, 스킬 함수) 형태
    # 새 논문 소스(예: IEEE Xplore) 추가 시 이 목록에 항목을 추가하면 됨
    _SKILLS = [
        ("arxiv",    arxiv.run),    # arXiv 프리프린트 서버 (최신 논문)
        ("semantic", semantic.run), # Semantic Scholar (인용 정보 포함)
    ]

    def run(self) -> list[dict]:
        """
        모든 논문 스킬을 병렬 실행하고 결과를 합쳐 반환한다.

        반환:
            중복 제거 + MBSE 관련도 내림차순 정렬된 논문 아이템 목록
        """
        all_items: list[dict] = []

        # max_workers = 스킬 수만큼 스레드 생성 → 모든 스킬이 동시에 실행
        with ThreadPoolExecutor(max_workers=len(self._SKILLS)) as pool:
            # 각 스킬을 스레드풀에 제출하고 future:이름 매핑 생성
            futures = {pool.submit(fn): name for name, fn in self._SKILLS}

            # 완료된 스킬부터 순서대로 결과 수집
            for future in as_completed(futures):
                name = futures[future]
                try:
                    all_items.extend(future.result())
                    print(f"  [PaperAgent] {name} 완료")
                except Exception as e:
                    # 스킬 하나가 실패해도 나머지 결과는 유지
                    print(f"  [PaperAgent] {name} 실패: {e}")

        # 중복 제거 후 MBSE 관련도 점수 내림차순 정렬
        return sorted(self._dedup(all_items), key=score_mbse_relevance, reverse=True)

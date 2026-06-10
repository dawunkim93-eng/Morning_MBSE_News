# ─────────────────────────────────────────────────────────────────────────────
# 파일    : agents/base.py
# 설명    : 모든 Python 에이전트가 상속하는 추상 기반 클래스(BaseAgent).
#           공통 인터페이스(run)와 중복 제거 유틸리티(_dedup)를 정의한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — 추상 클래스 및 공통 dedup 메서드 정의
# ─────────────────────────────────────────────────────────────────────────────

from abc import ABC, abstractmethod


class BaseAgent(ABC):
    """
    모든 Python 에이전트의 기반 클래스.

    하위 클래스는 반드시 run() 메서드를 구현해야 한다.
    각 에이전트는 run()을 통해 수집된 아이템 목록을 반환한다.
    """

    @abstractmethod
    def run(self) -> list[dict]:
        """
        에이전트 핵심 로직을 실행하고 결과 아이템 목록을 반환한다.

        반환:
            {"title": str, "link": str, "summary": str, ...} 형태의 딕셔너리 목록
        """
        pass

    @staticmethod
    def _dedup(items: list[dict]) -> list[dict]:
        """
        제목(title)을 기준으로 중복 아이템을 제거한다.

        여러 소스에서 동일한 기사나 논문이 수집될 수 있으므로
        첫 번째 등장한 아이템만 유지한다.

        매개변수:
            items : 중복 가능성이 있는 아이템 목록
        반환:
            중복이 제거된 아이템 목록 (입력 순서 유지)
        """
        seen, result = set(), []
        for item in items:
            if item["title"] not in seen:
                seen.add(item["title"])
                result.append(item)
        return result

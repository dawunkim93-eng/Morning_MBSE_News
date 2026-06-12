# ─────────────────────────────────────────────────────────────────────────────
# 파일    : main.py
# 설명    : 프로그램 진입점. orchestrator.py 의 asyncio 파이프라인을 실행한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — Orchestrator 클래스 호출 진입점
#   v1.1   2026-06-12   버그 수정 — orchestrator.py 의 async main() 으로 교체
#                                   (Orchestrator 클래스 임포트 오류 수정)
# ─────────────────────────────────────────────────────────────────────────────

import asyncio
import sys

# orchestrator.py 의 async def main() 을 가져와 실행
from orchestrator import main as run_pipeline

if __name__ == "__main__":
    dry_run = "--dry-run" in sys.argv
    asyncio.run(run_pipeline(dry_run))

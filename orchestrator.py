# ─────────────────────────────────────────────────────────────────────────────
# 파일    : orchestrator.py
# 설명    : asyncio 기반 에이전트 파이프라인 오케스트레이터
#           bash 에이전트 스크립트를 3단계 순서로 실행·조율한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — asyncio 멀티에이전트 파이프라인 구현
# ─────────────────────────────────────────────────────────────────────────────
#
# 실행 흐름:
#   Phase 1 (병렬) : agent1_news.sh  ║  agent2_papers.sh
#   Phase 2 (순차) : agent3_summarize.sh
#   Phase 3 (순차) : agent4_send.sh
#
# 사용법:
#   python orchestrator.py             # 정상 실행 (텔레그램 발송)
#   python orchestrator.py --dry-run   # 텔레그램 발송 생략, 출력만 확인

import asyncio
import os
import sys
from datetime import datetime
from pathlib import Path

# 프로젝트 루트 디렉터리 (이 파일이 위치한 폴더)
BASE_DIR = Path(__file__).parent

# 에이전트 하나당 최대 대기 시간 (초)
AGENT_TIMEOUT = 120


async def run_agent(
    name: str,
    script: str,
    env: dict[str, str] | None = None,
    timeout: int = AGENT_TIMEOUT,
) -> int:
    """
    bash 에이전트 스크립트를 비동기로 실행하고 종료 코드를 반환한다.

    매개변수:
        name    : 로그에 표시할 에이전트 이름
        script  : BASE_DIR 기준 bash 스크립트 경로 (예: "agents/agent1_news.sh")
        env     : 추가 환경변수 dict (기존 os.environ 위에 덮어씀)
        timeout : 최대 실행 시간 (초). 초과 시 프로세스 강제 종료
    반환:
        프로세스 종료 코드 (0 = 성공, 0이 아니면 실패)
    """
    script_path = BASE_DIR / script

    # 스크립트 파일 존재 여부 확인
    if not script_path.exists():
        print(f"[orchestrator] ERROR: {script_path} 파일 없음", file=sys.stderr)
        return 1

    # 부모 환경변수에 추가 변수를 병합
    merged_env = {**os.environ, **(env or {})}

    t0 = datetime.now()
    print(f"[{t0.strftime('%H:%M:%S')}] ▶ {name} 시작")

    # asyncio 서브프로세스로 bash 스크립트 실행
    proc = await asyncio.create_subprocess_exec(
        "bash", str(script_path),
        stdout=asyncio.subprocess.PIPE,  # 표준 출력 캡처
        stderr=asyncio.subprocess.PIPE,  # 표준 에러 캡처
        env=merged_env,
        cwd=str(BASE_DIR),               # 작업 디렉터리를 프로젝트 루트로 설정
    )

    try:
        # timeout 초 안에 완료되지 않으면 TimeoutError 발생
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        elapsed = (datetime.now() - t0).seconds
        print(f"[orchestrator] ✗ {name} 타임아웃 ({elapsed}s 초과)", file=sys.stderr)
        return 1

    elapsed = (datetime.now() - t0).seconds
    code = proc.returncode

    # stderr 내용을 들여쓰기로 출력 (에이전트 내부 로그)
    if stderr:
        for line in stderr.decode(errors="replace").strip().splitlines():
            print(f"  {line}", file=sys.stderr)

    status = "✓" if code == 0 else "✗"
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {status} {name} "
          f"완료 — {elapsed}s (종료코드={code})")
    return code


async def main(dry_run: bool = False) -> None:
    """
    파이프라인 전체를 3단계로 실행한다.

    dry_run=True 이면 DRY_RUN=1 환경변수를 에이전트에 전달해
    텔레그램 발송을 건너뛴다.
    """
    # DRY_RUN 플래그를 환경변수로 에이전트에 전달
    env: dict[str, str] = {"DRY_RUN": "1"} if dry_run else {}

    if dry_run:
        print("[orchestrator] ── DRY-RUN 모드 (텔레그램 발송 생략) ──")

    # ── Phase 1: 뉴스 + 논문 수집 (병렬) ────────────────────────────────────
    # 두 에이전트를 동시에 실행해 전체 대기 시간을 단축
    print("\n[orchestrator] ══ Phase 1: 뉴스 + 논문 수집 (병렬) ══")
    results = await asyncio.gather(
        run_agent("agent1_news",   "agents/agent1_news.sh",   env),
        run_agent("agent2_papers", "agents/agent2_papers.sh", env),
        return_exceptions=True,  # 한 쪽이 실패해도 다른 쪽 결과를 받기 위해
    )

    # 어느 한 에이전트라도 실패하면 전체 파이프라인 중단
    for i, r in enumerate(results):
        if isinstance(r, Exception) or r != 0:
            print(f"[orchestrator] Phase 1 실패 (agent {i+1}): {r}", file=sys.stderr)
            sys.exit(1)

    # ── Phase 2: Claude API로 요약 + 분류 + 랭킹 ────────────────────────────
    print("\n[orchestrator] ══ Phase 2: 요약 (Claude API) ══")
    code = await run_agent("agent3_summarize", "agents/agent3_summarize.sh", env)
    if code != 0:
        print("[orchestrator] Phase 2 실패", file=sys.stderr)
        sys.exit(1)

    # ── Phase 3: 텔레그램 발송 + 캐시 저장 + 로그 기록 ─────────────────────
    print("\n[orchestrator] ══ Phase 3: 텔레그램 발송 ══")
    code = await run_agent("agent4_send", "agents/agent4_send.sh", env)
    if code != 0:
        print("[orchestrator] Phase 3 실패", file=sys.stderr)
        sys.exit(1)

    print("\n[orchestrator] ══ 파이프라인 전체 완료 ══")


if __name__ == "__main__":
    # 커맨드라인 인자에 --dry-run 이 있으면 테스트 모드 활성화
    dry_run = "--dry-run" in sys.argv
    asyncio.run(main(dry_run))

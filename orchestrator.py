"""
orchestrator.py — asyncio-based pipeline coordinator

Phase 1 (parallel):  agent1_news.sh  ║  agent2_papers.sh
Phase 2 (sequential): agent3_summarize.sh
Phase 3 (sequential): agent4_send.sh

Usage:
    python orchestrator.py            # normal run
    python orchestrator.py --dry-run  # skip Telegram send
"""
import asyncio
import os
import sys
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).parent
AGENT_TIMEOUT = 120  # seconds per agent


async def run_agent(
    name: str,
    script: str,
    env: dict[str, str] | None = None,
    timeout: int = AGENT_TIMEOUT,
) -> int:
    script_path = BASE_DIR / script
    if not script_path.exists():
        print(f"[orchestrator] ERROR: {script_path} not found", file=sys.stderr)
        return 1

    merged_env = {**os.environ, **(env or {})}
    t0 = datetime.now()
    print(f"[{t0.strftime('%H:%M:%S')}] ▶ {name} started")

    proc = await asyncio.create_subprocess_exec(
        "bash", str(script_path),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=merged_env,
        cwd=str(BASE_DIR),
    )

    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        elapsed = (datetime.now() - t0).seconds
        print(f"[orchestrator] ✗ {name} timed out after {elapsed}s", file=sys.stderr)
        return 1

    elapsed = (datetime.now() - t0).seconds
    code = proc.returncode

    if stderr:
        for line in stderr.decode(errors="replace").strip().splitlines():
            print(f"  {line}", file=sys.stderr)

    status = "✓" if code == 0 else "✗"
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {status} {name} "
          f"finished in {elapsed}s (exit={code})")
    return code


async def main(dry_run: bool = False) -> None:
    env: dict[str, str] = {"DRY_RUN": "1"} if dry_run else {}

    if dry_run:
        print("[orchestrator] ── DRY-RUN MODE (Telegram send will be skipped) ──")

    # ── Phase 1: parallel ──────────────────────────────────────────────────
    print("\n[orchestrator] ══ Phase 1: News + Papers (parallel) ══")
    results = await asyncio.gather(
        run_agent("agent1_news",   "agents/agent1_news.sh",   env),
        run_agent("agent2_papers", "agents/agent2_papers.sh", env),
        return_exceptions=True,
    )
    for i, r in enumerate(results):
        if isinstance(r, Exception) or r != 0:
            print(f"[orchestrator] Phase 1 failed (agent {i+1}): {r}", file=sys.stderr)
            sys.exit(1)

    # ── Phase 2: summarize ─────────────────────────────────────────────────
    print("\n[orchestrator] ══ Phase 2: Summarize ══")
    code = await run_agent("agent3_summarize", "agents/agent3_summarize.sh", env)
    if code != 0:
        print("[orchestrator] Phase 2 failed", file=sys.stderr)
        sys.exit(1)

    # ── Phase 3: send ──────────────────────────────────────────────────────
    print("\n[orchestrator] ══ Phase 3: Send ══")
    code = await run_agent("agent4_send", "agents/agent4_send.sh", env)
    if code != 0:
        print("[orchestrator] Phase 3 failed", file=sys.stderr)
        sys.exit(1)

    print("\n[orchestrator] ══ Pipeline completed successfully ══")


if __name__ == "__main__":
    dry_run = "--dry-run" in sys.argv
    asyncio.run(main(dry_run))

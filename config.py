# ─────────────────────────────────────────────────────────────────────────────
# 파일    : config.py
# 설명    : 전체 프로젝트에서 공유하는 설정값 및 상수 정의.
#           검색 키워드는 keyword_loader.py 를 통해 keywords/*.yml 플러그인에서
#           동적으로 로드된다. 새 키워드를 추가하려면 이 파일이 아닌
#           keywords/ 폴더에 .yml 파일을 추가하면 된다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — 환경변수 로드, HTTP 헤더, 시간대 정의
#   v1.1   2026-06-10   키워드를 keyword_loader 플러그인에서 동적 로드로 변경
# ─────────────────────────────────────────────────────────────────────────────

import os
from datetime import timezone, timedelta

# ── 텔레그램 인증 정보 (환경변수에서 로드) ────────────────────────────────────
TELEGRAM_TOKEN = os.environ.get("TELEGRAM_TOKEN", "")
CHAT_ID        = os.environ.get("TELEGRAM_CHAT_ID", "")

# ── HTTP 요청 헤더 ─────────────────────────────────────────────────────────────
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    )
}

# ── 시간대 설정 ────────────────────────────────────────────────────────────────
KST = timezone(timedelta(hours=9))  # 한국 표준시 (UTC+9)

# ── 키워드 플러그인 로더 ──────────────────────────────────────────────────────
# keywords/*.yml 플러그인 파일에서 키워드를 동적으로 로드한다.
# 로더를 임포트할 수 없거나 플러그인이 없으면 내장 기본값을 사용한다.
try:
    from keyword_loader import (
        get_naver_keywords,
        get_google_queries,
        get_arxiv_queries,
        get_semantic_query,
    )
    NAVER_KEYWORDS         = get_naver_keywords()
    GOOGLE_NEWS_QUERIES    = get_google_queries()
    ARXIV_QUERIES          = get_arxiv_queries()
    SEMANTIC_SCHOLAR_QUERY = get_semantic_query()

except Exception as e:
    # keyword_loader 또는 pyyaml 미설치 시 기본값으로 폴백
    print(f"[config] 키워드 로더 사용 불가 ({e}), 기본값 사용")
    NAVER_KEYWORDS         = ["MBSE", "Model-Based Systems Engineering", "SysML", "시스템 엔지니어링"]
    GOOGLE_NEWS_QUERIES    = ["MBSE systems engineering", "Model-Based Systems Engineering"]
    ARXIV_QUERIES          = ["Model-Based Systems Engineering", "SysML MBSE"]
    SEMANTIC_SCHOLAR_QUERY = "Model-Based Systems Engineering MBSE SysML"

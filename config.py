# ─────────────────────────────────────────────────────────────────────────────
# 파일    : config.py
# 설명    : 전체 프로젝트에서 공유하는 설정값 및 상수 정의.
#           민감 정보(토큰, ID)는 환경변수에서 읽어오며 코드에 직접 기재하지 않는다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — 환경변수 로드, 검색 키워드, HTTP 헤더 정의
# ─────────────────────────────────────────────────────────────────────────────

import os
from datetime import timezone, timedelta

# ── 텔레그램 인증 정보 (환경변수에서 로드) ────────────────────────────────────
# GitHub Actions Secrets 또는 로컬 .env 파일에 설정
TELEGRAM_TOKEN = os.environ.get("TELEGRAM_TOKEN", "")
CHAT_ID        = os.environ.get("TELEGRAM_CHAT_ID", "")

# ── HTTP 요청 헤더 ─────────────────────────────────────────────────────────────
# 봇 차단을 피하기 위해 일반 브라우저처럼 보이는 User-Agent 사용
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    )
}

# ── 시간대 설정 ────────────────────────────────────────────────────────────────
# 한국 표준시 (UTC+9)
KST = timezone(timedelta(hours=9))

# ── 네이버 뉴스 검색 키워드 ───────────────────────────────────────────────────
# 한국어 뉴스 검색 시 사용되는 키워드 목록
NAVER_KEYWORDS = [
    "MBSE",
    "Model-Based Systems Engineering",
    "SysML",
    "시스템 엔지니어링",
    "MOSA",
]

# ── Google News RSS 검색 쿼리 ─────────────────────────────────────────────────
# 영어 뉴스 검색 시 사용되는 쿼리 문자열 목록
GOOGLE_NEWS_QUERIES = [
    "MBSE systems engineering",
    "Model-Based Systems Engineering",
    "SysML modeling",
]

# ── arXiv 논문 검색 쿼리 ──────────────────────────────────────────────────────
# arXiv API의 all: 필드에 전달되는 검색어 목록
ARXIV_QUERIES = [
    "Model-Based Systems Engineering",
    "SysML MBSE",
    "MBSE digital twin",
]

# ── Semantic Scholar 논문 검색 쿼리 ──────────────────────────────────────────
# Semantic Scholar API에 전달되는 단일 검색어
SEMANTIC_SCHOLAR_QUERY = "Model-Based Systems Engineering MBSE SysML"

import os
from datetime import timezone, timedelta

TELEGRAM_TOKEN = os.environ.get("TELEGRAM_TOKEN", "")
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    )
}

KST = timezone(timedelta(hours=9))

NAVER_KEYWORDS = [
    "MBSE",
    "Model-Based Systems Engineering",
    "SysML",
    "시스템 엔지니어링",
    "MOSA",
]

GOOGLE_NEWS_QUERIES = [
    "MBSE systems engineering",
    "Model-Based Systems Engineering",
    "SysML modeling",
]

ARXIV_QUERIES = [
    "Model-Based Systems Engineering",
    "SysML MBSE",
    "MBSE digital twin",
]

SEMANTIC_SCHOLAR_QUERY = "Model-Based Systems Engineering MBSE SysML"

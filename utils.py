import re

try:
    from deep_translator import GoogleTranslator
    _TRANSLATOR_OK = True
except ImportError:
    _TRANSLATOR_OK = False


def translate_to_korean(text: str) -> str:
    if not text or not _TRANSLATOR_OK:
        return text
    try:
        result = GoogleTranslator(source="auto", target="ko").translate(text)
        return result or text
    except Exception as e:
        print(f"  [번역 실패] {e}")
        return text


def smart_truncate(text: str, max_sentences: int = 3) -> str:
    """문장 단위로 max_sentences개까지만 반환. 경계 없으면 전체 반환."""
    if not text:
        return text
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    if len(sentences) <= max_sentences:
        return text.strip()
    return " ".join(sentences[:max_sentences]).rstrip()


# ── MBSE 관련도 점수 ───────────────────────────────
_CORE: dict[str, int] = {
    "mbse": 10,
    "model-based systems engineering": 10,
    "model based systems engineering": 10,
    "모델 기반 시스템 엔지니어링": 10,
    "sysml": 8,
    "mosa": 7,
    "모델기반": 5,
    "model-based": 5,
}

_RELATED: dict[str, int] = {
    "incose": 6,
    "systems engineering": 4,
    "시스템 엔지니어링": 4,
    "system architecture": 3,
    "systems architecture": 3,
    "system modeling": 3,
    "digital twin": 3,
    "디지털 트윈": 3,
    "requirements management": 3,
    "ontology": 2,
    "verification": 2,
    "validation": 2,
    "uml": 2,
}


def score_mbse_relevance(item: dict) -> int:
    """제목(2배)과 요약(1배)에서 MBSE 관련 키워드 가중합 반환."""
    title = (item.get("title") or "").lower()
    summary = (item.get("summary") or "").lower()
    score = 0
    for kw, w in _CORE.items():
        if kw in title:
            score += w * 2
        if kw in summary:
            score += w
    for kw, w in _RELATED.items():
        if kw in title:
            score += w * 2
        if kw in summary:
            score += w
    return score

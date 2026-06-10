# ─────────────────────────────────────────────────────────────────────────────
# 파일    : utils.py
# 설명    : 프로젝트 전역 유틸리티 함수 모음.
#           번역, 문장 단위 자르기, MBSE 관련도 점수 계산 기능을 제공한다.
#           점수 가중치(_CORE, _RELATED)는 keyword_loader 플러그인에서 동적 로드된다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — 번역, 문장 자르기, 관련도 점수 함수 구현
#   v1.1   2026-06-10   _CORE/_RELATED 를 keyword_loader 플러그인에서 동적 로드로 변경
# ─────────────────────────────────────────────────────────────────────────────

import re

# deep-translator 없는 환경에서도 임포트 오류 없이 동작
try:
    from deep_translator import GoogleTranslator
    _TRANSLATOR_OK = True
except ImportError:
    _TRANSLATOR_OK = False


# ── 번역 ─────────────────────────────────────────────────────────────────────

def translate_to_korean(text: str) -> str:
    """
    텍스트를 한국어로 번역한다. 실패 시 원문 반환.
    """
    if not text or not _TRANSLATOR_OK:
        return text
    try:
        result = GoogleTranslator(source="auto", target="ko").translate(text)
        return result or text
    except Exception as e:
        print(f"  [번역 실패] {e}")
        return text


# ── 문장 단위 자르기 ─────────────────────────────────────────────────────────

def smart_truncate(text: str, max_sentences: int = 3) -> str:
    """
    텍스트를 문장 단위로 max_sentences 개까지 자른다.
    문장 경계(. ! ?)가 없으면 전체를 반환한다.
    """
    if not text:
        return text
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    if len(sentences) <= max_sentences:
        return text.strip()
    return " ".join(sentences[:max_sentences]).rstrip()


# ── MBSE 관련도 점수 ──────────────────────────────────────────────────────────
# 가중치를 keyword_loader 플러그인에서 동적으로 로드한다.
# 플러그인을 사용할 수 없으면 기본값으로 폴백한다.

try:
    from keyword_loader import get_scoring_weights
    _CORE, _RELATED = get_scoring_weights()
except Exception:
    # pyyaml 미설치 또는 keywords/ 없을 때 기본값
    _CORE: dict[str, int] = {
        "mbse": 10,
        "model-based systems engineering": 10,
        "sysml": 8,
        "mosa": 7,
        "model-based": 5,
    }
    _RELATED: dict[str, int] = {
        "incose": 6,
        "systems engineering": 4,
        "시스템 엔지니어링": 4,
        "digital twin": 3,
        "디지털 트윈": 3,
        "verification": 2,
        "validation": 2,
        "uml": 2,
    }


def score_mbse_relevance(item: dict) -> int:
    """
    뉴스/논문 아이템의 MBSE 관련도 점수를 계산한다.
    제목 매칭은 2배 가중치, 요약 매칭은 1배 가중치를 적용한다.
    가중치 기준은 keywords/*.yml 플러그인에서 동적으로 로드된다.
    """
    title   = (item.get("title")   or "").lower()
    summary = (item.get("summary") or "").lower()
    score   = 0
    for kw, w in _CORE.items():
        if kw in title:   score += w * 2
        if kw in summary: score += w
    for kw, w in _RELATED.items():
        if kw in title:   score += w * 2
        if kw in summary: score += w
    return score

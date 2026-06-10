# ─────────────────────────────────────────────────────────────────────────────
# 파일    : utils.py
# 설명    : 프로젝트 전역 유틸리티 함수 모음.
#           번역, 문장 단위 자르기, MBSE 관련도 점수 계산 기능을 제공한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — 번역, 문장 자르기, 관련도 점수 함수 구현
# ─────────────────────────────────────────────────────────────────────────────

import re

# deep-translator 패키지가 없는 환경(예: 설치 전)에서도 임포트 오류 없이 동작
try:
    from deep_translator import GoogleTranslator
    _TRANSLATOR_OK = True
except ImportError:
    _TRANSLATOR_OK = False


# ── 번역 ─────────────────────────────────────────────────────────────────────

def translate_to_korean(text: str) -> str:
    """
    텍스트를 한국어로 번역한다.

    - deep-translator 패키지가 없거나 번역 실패 시 원문을 그대로 반환 (폴백)
    - 이미 한국어인 텍스트는 그대로 반환됨 (Google이 자동 감지)

    매개변수:
        text : 번역할 원문 문자열
    반환:
        번역된 한국어 문자열 (실패 시 원문)
    """
    if not text or not _TRANSLATOR_OK:
        return text
    try:
        result = GoogleTranslator(source="auto", target="ko").translate(text)
        return result or text
    except Exception as e:
        print(f"  [번역 실패] {e}")
        return text  # 번역 실패 시 원문 반환


# ── 문장 단위 자르기 ─────────────────────────────────────────────────────────

def smart_truncate(text: str, max_sentences: int = 3) -> str:
    """
    텍스트를 문장 단위로 잘라 max_sentences 개까지만 반환한다.

    글자 수로 단순히 자르는 방식과 달리, 문장 끝(. ! ?)을 기준으로
    자르기 때문에 문맥이 자연스럽게 유지된다.
    문장 경계가 없으면 원문 전체를 반환한다.

    매개변수:
        text          : 원본 텍스트
        max_sentences : 유지할 최대 문장 수 (기본값 3)
    반환:
        잘린 텍스트 문자열
    """
    if not text:
        return text
    # 마침표·느낌표·물음표 뒤 공백을 문장 경계로 분리
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    if len(sentences) <= max_sentences:
        return text.strip()  # 이미 max_sentences 이하면 전체 반환
    return " ".join(sentences[:max_sentences]).rstrip()


# ── MBSE 관련도 점수 ──────────────────────────────────────────────────────────
#
# 핵심 키워드(_CORE)와 관련 키워드(_RELATED)에 가중치를 부여해
# 뉴스·논문의 MBSE 관련도를 정수 점수로 수치화한다.
# 제목에 등장하면 2배 가중치를 적용한다 (제목이 더 신뢰성 높음).

_CORE: dict[str, int] = {
    "mbse": 10,                              # MBSE 약어 (가장 직접적인 키워드)
    "model-based systems engineering": 10,   # MBSE 공식 명칭 (영어)
    "model based systems engineering": 10,   # 하이픈 없는 변형
    "모델 기반 시스템 엔지니어링": 10,            # MBSE 공식 명칭 (한국어)
    "sysml": 8,                              # MBSE 표준 모델링 언어
    "mosa": 7,                               # Modular Open Systems Approach
    "모델기반": 5,                             # 한국어 축약 표현
    "model-based": 5,                        # 일반적인 model-based 표현
}

_RELATED: dict[str, int] = {
    "incose": 6,                    # 국제 시스템 엔지니어링 협회
    "systems engineering": 4,       # 시스템 엔지니어링 (영어)
    "시스템 엔지니어링": 4,             # 시스템 엔지니어링 (한국어)
    "system architecture": 3,       # 시스템 아키텍처
    "systems architecture": 3,      # systems architecture (복수형)
    "system modeling": 3,           # 시스템 모델링
    "digital twin": 3,              # 디지털 트윈 (MBSE와 밀접한 연관)
    "디지털 트윈": 3,                  # 디지털 트윈 (한국어)
    "requirements management": 3,   # 요구사항 관리
    "ontology": 2,                  # 온톨로지 (시스템 모델과 연관)
    "verification": 2,              # 검증 (V&V 프로세스)
    "validation": 2,                # 확인 (V&V 프로세스)
    "uml": 2,                       # UML (SysML의 기반 언어)
}


def score_mbse_relevance(item: dict) -> int:
    """
    뉴스/논문 아이템의 MBSE 관련도 점수를 계산한다.

    계산 방식:
        - 제목(title)에 키워드가 있으면 가중치 × 2
        - 요약(summary)에 키워드가 있으면 가중치 × 1
        - _CORE 키워드가 _RELATED 키워드보다 높은 가중치

    매개변수:
        item : {"title": str, "summary": str, ...} 형태의 딕셔너리
    반환:
        관련도 점수 (정수, 높을수록 관련성 높음)
    """
    title   = (item.get("title")   or "").lower()
    summary = (item.get("summary") or "").lower()
    score   = 0

    for kw, w in _CORE.items():
        if kw in title:   score += w * 2  # 제목 매칭: 2배 가중치
        if kw in summary: score += w

    for kw, w in _RELATED.items():
        if kw in title:   score += w * 2  # 제목 매칭: 2배 가중치
        if kw in summary: score += w

    return score

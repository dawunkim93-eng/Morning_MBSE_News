# ─────────────────────────────────────────────────────────────────────────────
# 파일    : skills/translate.py
# 설명    : 번역 및 문장 자르기 스킬.
#           deep-translator 라이브러리를 사용해 텍스트를 한국어로 번역하고,
#           긴 텍스트를 문장 단위로 자른다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — translate, smart_truncate 함수 구현
# ─────────────────────────────────────────────────────────────────────────────

import re

# deep-translator 없는 환경에서도 임포트 오류 없이 동작하도록 예외 처리
try:
    from deep_translator import GoogleTranslator
    _OK = True
except ImportError:
    _OK = False


def translate(text: str) -> str:
    """
    텍스트를 한국어로 번역한다 (Google 번역 사용).

    - 패키지 미설치 또는 번역 실패 시 원문 반환 (폴백)
    - 이미 한국어인 텍스트는 변환 없이 그대로 반환됨

    매개변수:
        text : 번역할 원문 텍스트
    반환:
        번역된 한국어 텍스트 (실패 시 원문)
    """
    if not text or not _OK:
        return text
    try:
        return GoogleTranslator(source="auto", target="ko").translate(text) or text
    except Exception as e:
        print(f"  [번역 실패] {e}")
        return text  # 번역 실패 시 원문 반환


def smart_truncate(text: str, max_sentences: int = 3) -> str:
    """
    텍스트를 문장 단위로 잘라 max_sentences 개까지만 반환한다.

    문장 끝(. ! ?)을 기준으로 자르므로 문맥이 자연스럽게 유지된다.
    문장 경계를 찾을 수 없으면 원문 전체를 반환한다.

    매개변수:
        text          : 원본 텍스트
        max_sentences : 유지할 최대 문장 수 (기본값 3)
    반환:
        잘린 텍스트
    """
    if not text:
        return text
    # 마침표·느낌표·물음표 뒤 공백을 문장 경계로 분리
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    if len(sentences) <= max_sentences:
        return text.strip()
    return " ".join(sentences[:max_sentences]).rstrip()

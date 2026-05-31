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
    # 마침표/느낌표/물음표 뒤 공백 또는 끝을 문장 경계로 처리
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    if len(sentences) <= max_sentences:
        return text.strip()
    return " ".join(sentences[:max_sentences]).rstrip()

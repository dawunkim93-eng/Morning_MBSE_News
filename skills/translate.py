import re

try:
    from deep_translator import GoogleTranslator
    _OK = True
except ImportError:
    _OK = False


def translate(text: str) -> str:
    if not text or not _OK:
        return text
    try:
        return GoogleTranslator(source="auto", target="ko").translate(text) or text
    except Exception as e:
        print(f"  [번역 실패] {e}")
        return text


def smart_truncate(text: str, max_sentences: int = 3) -> str:
    if not text:
        return text
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    if len(sentences) <= max_sentences:
        return text.strip()
    return " ".join(sentences[:max_sentences]).rstrip()

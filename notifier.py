# ─────────────────────────────────────────────────────────────────────────────
# 파일    : notifier.py
# 설명    : 텔레그램 메시지 전송 유틸리티.
#           HTML parse_mode 를 사용해 제목 굵게 표시, URL 앵커 링크 등을 지원한다.
#           메시지가 4000자를 초과하면 자동으로 분할해 여러 번 전송한다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — HTML 모드 전송, 4000자 청크 분할, 예외 re-raise
# ─────────────────────────────────────────────────────────────────────────────

import requests
from config import TELEGRAM_TOKEN, CHAT_ID


def send_telegram(message: str) -> None:
    """
    텔레그램 봇 API를 통해 메시지를 전송한다.

    - parse_mode=HTML 이므로 메시지 내 <b>, <a href>, <i> 태그 사용 가능
    - '&', '<', '>' 등 HTML 특수문자는 반드시 html.escape() 처리 후 전달할 것
    - 전송 실패 시 RuntimeError를 발생시켜 GitHub Actions 가 실패로 감지하게 함

    매개변수:
        message : 전송할 HTML 형식의 메시지 문자열
    """
    # 환경변수 누락 시 즉시 오류 발생 — 설정 오류를 빠르게 감지
    if not TELEGRAM_TOKEN or not CHAT_ID:
        raise EnvironmentError(
            "TELEGRAM_TOKEN 또는 TELEGRAM_CHAT_ID 환경변수가 설정되지 않았습니다."
        )

    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"

    # 텔레그램 API 최대 메시지 길이(4096자)를 초과할 경우 4000자씩 분할 전송
    for chunk in [message[i:i + 4000] for i in range(0, len(message), 4000)]:
        try:
            resp = requests.post(
                url,
                data={"chat_id": CHAT_ID, "text": chunk, "parse_mode": "HTML"},
                timeout=10,
            )
            # HTTP 4xx/5xx 응답이면 예외 발생
            resp.raise_for_status()
        except requests.RequestException as e:
            # 예외를 다시 던져 상위 호출자(GitHub Actions 등)가 실패를 감지하도록 함
            raise RuntimeError(
                f"텔레그램 전송 실패: {e}\n"
                f"응답 본문: {getattr(e.response, 'text', '없음')}"
            ) from e

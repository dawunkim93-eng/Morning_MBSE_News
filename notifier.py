import requests
from config import TELEGRAM_TOKEN, CHAT_ID


def send_telegram(message: str) -> None:
    if not TELEGRAM_TOKEN or not CHAT_ID:
        raise EnvironmentError("TELEGRAM_TOKEN 또는 TELEGRAM_CHAT_ID 환경변수가 설정되지 않았습니다.")

    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    for chunk in [message[i:i + 4000] for i in range(0, len(message), 4000)]:
        try:
            resp = requests.post(
                url, data={"chat_id": CHAT_ID, "text": chunk}, timeout=10
            )
            resp.raise_for_status()
        except requests.RequestException as e:
            print(f"  텔레그램 전송 실패: {e}")

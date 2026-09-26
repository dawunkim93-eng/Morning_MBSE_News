# ─────────────────────────────────────────────────────────────────────────────
# 파일    : keyword_loader.py
# 설명    : keywords/ 디렉터리의 YAML 플러그인 파일들을 로드·병합하는 모듈.
#           Python 코드(config.py, utils.py)와 bash 스크립트(skills.sh) 양쪽에서
#           CLI 또는 import 방식으로 사용할 수 있다.
#
#           새 키워드 추가 방법:
#             keywords/ 폴더에 .yml 파일을 추가하기만 하면 자동으로 반영된다.
#             기존 코드를 수정할 필요가 없다.
# ─────────────────────────────────────────────────────────────────────────────
# 수정 이력
#   버전    날짜          내용
#   v1.0   2026-06-10   최초 작성 — YAML 플러그인 로더 및 CLI 인터페이스 구현
# ─────────────────────────────────────────────────────────────────────────────
#
# CLI 사용법 (bash에서):
#   python3 keyword_loader.py --format naver      # 네이버 키워드 목록 출력
#   python3 keyword_loader.py --format filter     # grep 패턴 출력
#   python3 keyword_loader.py --format all        # 전체 JSON 출력
#   python3 keyword_loader.py --list-plugins      # 로드된 플러그인 목록

import json
import sys
import argparse
from pathlib import Path

# keywords/ 플러그인 디렉터리 경로 (이 파일 기준)
KEYWORDS_DIR = Path(__file__).parent / "keywords"

# yaml 없을 때 기본값으로 폴백
try:
    import yaml
    _YAML_OK = True
except ImportError:
    _YAML_OK = False

# ── 기본 폴백 키워드 (yaml/keywords/ 모두 없을 때 사용) ──────────────────────
_FALLBACK = {
    "naver":            ["MBSE", "Model-Based Systems Engineering", "SysML", "시스템 엔지니어링"],
    "google_news":      ["MBSE systems engineering", "Model-Based Systems Engineering"],
    "arxiv":            ["Model-Based Systems Engineering", "SysML MBSE"],
    "semantic_scholar": "Model-Based Systems Engineering MBSE SysML",
    "filter":           ["MBSE", "SysML", "model-based", "systems engineering"],
    "scoring": {
        "core":    {"mbse": 10, "sysml": 8, "model-based systems engineering": 10},
        "related": {"systems engineering": 4, "digital twin": 3, "incose": 6},
    },
}


# ═════════════════════════════════════════════════════════════════════════════
# 내부 로더
# ═════════════════════════════════════════════════════════════════════════════

def _load_yaml(path: Path) -> dict:
    """단일 YAML 파일을 로드한다. 실패 시 빈 딕셔너리를 반환한다."""
    if not _YAML_OK:
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
            return data if isinstance(data, dict) else {}
    except Exception as e:
        print(f"[keyword_loader] 경고: {path.name} 로드 실패 — {e}", file=sys.stderr)
        return {}


def load_plugins() -> list[dict]:
    """
    keywords/ 디렉터리의 모든 .yml 플러그인을 priority 오름차순으로 로드한다.

    반환:
        로드된 플러그인 딕셔너리 목록 (priority 오름차순, 없으면 빈 목록)
    """
    if not KEYWORDS_DIR.exists():
        print(f"[keyword_loader] 경고: {KEYWORDS_DIR} 없음 — 기본값 사용", file=sys.stderr)
        return []

    plugins = []
    for yml_file in sorted(KEYWORDS_DIR.glob("*.yml")):
        data = _load_yaml(yml_file)
        if data:
            data["_source"] = yml_file.name  # 출처 파일명 기록
            plugins.append(data)

    # priority 필드 오름차순 정렬 (없으면 99)
    return sorted(plugins, key=lambda x: x.get("priority", 99))


# ═════════════════════════════════════════════════════════════════════════════
# 공개 API — Python import 시 사용
# ═════════════════════════════════════════════════════════════════════════════

def get_naver_keywords() -> list[str]:
    """모든 플러그인의 naver 키워드를 중복 없이 합쳐 반환한다."""
    seen, result = set(), []
    for p in load_plugins():
        for kw in p.get("naver", []):
            if kw not in seen:
                seen.add(kw)
                result.append(kw)
    return result or _FALLBACK["naver"]


def get_google_queries() -> list[str]:
    """모든 플러그인의 google_news 쿼리를 중복 없이 합쳐 반환한다."""
    seen, result = set(), []
    for p in load_plugins():
        for q in p.get("google_news", []):
            if q not in seen:
                seen.add(q)
                result.append(q)
    return result or _FALLBACK["google_news"]


def get_arxiv_queries() -> list[str]:
    """모든 플러그인의 arxiv 쿼리를 중복 없이 합쳐 반환한다."""
    seen, result = set(), []
    for p in load_plugins():
        for q in p.get("arxiv", []):
            if q not in seen:
                seen.add(q)
                result.append(q)
    return result or _FALLBACK["arxiv"]


def get_semantic_query() -> str:
    """
    모든 플러그인의 semantic_scholar 쿼리를 공백으로 합쳐 반환한다.
    빈 문자열 플러그인은 건너뛴다.
    """
    parts = [
        p["semantic_scholar"]
        for p in load_plugins()
        if p.get("semantic_scholar", "").strip()
    ]
    return " ".join(parts) or _FALLBACK["semantic_scholar"]


def get_filter_terms() -> list[str]:
    """
    모든 플러그인의 filter 항목을 중복 없이 합쳐 반환한다.
    bash의 grep -E 패턴 생성에 사용된다.
    """
    seen, result = set(), []
    for p in load_plugins():
        for term in p.get("filter", []):
            if term not in seen:
                seen.add(term)
                result.append(term)
    return result or _FALLBACK["filter"]


def get_scoring_weights() -> tuple[dict[str, int], dict[str, int]]:
    """
    모든 플러그인의 scoring 가중치를 병합해 (core_dict, related_dict) 로 반환한다.
    같은 term이 여러 플러그인에 있으면 마지막 플러그인의 weight 가 적용된다.

    반환:
        (core_weights, related_weights) — {term: weight} 딕셔너리 튜플
    """
    core: dict[str, int]    = {}
    related: dict[str, int] = {}

    for p in load_plugins():
        scoring = p.get("scoring", {})
        for item in scoring.get("core", []):
            if isinstance(item, dict):
                core[item["term"]] = item["weight"]
        for item in scoring.get("related", []):
            if isinstance(item, dict):
                related[item["term"]] = item["weight"]

    # 플러그인에서 로드한 것이 없으면 기본값 사용
    if not core and not related:
        fb = _FALLBACK["scoring"]
        return fb["core"], fb["related"]
    return core, related


def list_plugins() -> list[dict]:
    """
    로드된 플러그인의 메타정보(이름, 파일, 우선순위)를 목록으로 반환한다.
    디버깅 및 확인 용도로 사용한다.
    """
    return [
        {
            "name":     p.get("name", "이름 없음"),
            "file":     p.get("_source", ""),
            "priority": p.get("priority", 99),
        }
        for p in load_plugins()
    ]


# ═════════════════════════════════════════════════════════════════════════════
# CLI 인터페이스 — bash 스크립트에서 사용
# ═════════════════════════════════════════════════════════════════════════════

def _cli():
    parser = argparse.ArgumentParser(
        description="MBSE 키워드 플러그인 로더 — keywords/*.yml 을 읽어 출력한다"
    )
    parser.add_argument(
        "--format",
        choices=["naver", "google", "arxiv", "semantic", "filter", "all"],
        default="all",
        help="출력할 키워드 형식 (기본값: all)",
    )
    parser.add_argument(
        "--separator",
        default="\n",
        help="항목 구분자 (기본값: 줄바꿈). bash grep 패턴용: --separator '|'",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="출력 항목 수 상한 (0 = 무제한). 목록 형식(naver/google/arxiv/filter)에만 적용되며, "
             "플러그인 priority 순서와 파일 내 쿼리 순서를 따른다.",
    )
    parser.add_argument(
        "--list-plugins",
        action="store_true",
        help="로드된 플러그인 목록을 JSON으로 출력",
    )
    args = parser.parse_args()

    # 이스케이프 시퀀스 처리 (쉘에서 \\n 으로 넘어오는 경우)
    sep = args.separator.replace("\\n", "\n").replace("\\|", "|")

    # limit > 0 이면 항목 수 상한 적용
    limit = args.limit if args.limit > 0 else None

    def _bounded(items: list[str]) -> list[str]:
        return items[:limit] if limit is not None else items

    if args.list_plugins:
        print(json.dumps(list_plugins(), ensure_ascii=False, indent=2))
        return

    if args.format == "naver":
        print(sep.join(_bounded(get_naver_keywords())))
    elif args.format == "google":
        print(sep.join(_bounded(get_google_queries())))
    elif args.format == "arxiv":
        print(sep.join(_bounded(get_arxiv_queries())))
    elif args.format == "semantic":
        print(get_semantic_query())
    elif args.format == "filter":
        # bash grep -E 용: | 구분자로 합쳐서 출력
        print(sep.join(_bounded(get_filter_terms())))
    elif args.format == "all":
        core, related = get_scoring_weights()
        output = {
            "naver":            get_naver_keywords(),
            "google_news":      get_google_queries(),
            "arxiv":            get_arxiv_queries(),
            "semantic_scholar": get_semantic_query(),
            "filter":           get_filter_terms(),
            "scoring": {
                "core":    core,
                "related": related,
            },
        }
        print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    _cli()

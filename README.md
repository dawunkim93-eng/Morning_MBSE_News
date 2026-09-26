# MBSE Letters (Morning_MBSE_News)

매일 아침 07:00 KST에 MBSE(Model-Based Systems Engineering) 관련 뉴스와 논문을
자동 수집·요약하고, 웹 사이트로 아카이브하는 파이프라인.

**사이트**: https://dawunkim93-eng.github.io/Morning_MBSE_News/

## 구성

```
agents/            파이프라인 에이전트 (bash)
├── agent1_news.sh      뉴스 수집 — Google News RSS(키워드+site:) + OMG pressroom
├── agent2_papers.sh    논문 수집 — arXiv + Semantic Scholar API
├── agent3_summarize.sh AI 한국어 요약·분류·랭킹 (OpenRouter→Anthropic 폴백)
└── agent4_commit.sh    data/YYYY-MM-DD.json 저장 + URL 캐시/로그

backfill/          과거 데이터 백필
├── arxiv_backfill.py   논문 전체 히스토리 (2007~), 월별 papers-YYYY-MM.json
└── news_backfill.py    뉴스 아카이브 + OMG 보도자료 전체, 월별 news-YYYY-MM.json

data/              사이트용 데이터 (매일 자동 커밋)
keywords/          검색 키워드 플러그인 (yml 추가만으로 확장)
site/              React+Vite 다크 테마 사이트 (GitHub Pages 배포)

.github/workflows/
├── daily_news.yml      매일 KST 07:00 크롤링→요약→data/ 커밋
├── deploy-pages.yml    site/·data/ 변경 시 gh-pages 자동 배포
└── backfill.yml        수동 백필 트리거 (scope: all/news/papers)
```

## 데이터 흐름

1. **수집** — `agent1/agent2` 병렬 크롤링 (키워드는 `keywords/*.yml` 단일 소스)
2. **요약** — Claude API로 상위 N건 한국어 3~5줄 요약 + 카테고리 분류 + 점수 랭킹
3. **저장** — `data/YYYY-MM-DD.json` 커밋 → 사이트 자동 재빌드

## 사이트 (MBSE Letters)

- **홈**: 오늘의 브리핑 (TODAY / 참고 구분 표시)
- **아카이브**: 뉴스·논문 탭, 카테고리 색상 태그, 출처 뱃지(OMG 공식/INCOSE/arXiv/뉴스),
  연도·카테고리 필터, 제목·초록·저자 검색, 논문 초록 접이식

## 키워드 조정

`keywords/*.yml` 수정만으로 수집 쿼리·필터·점수가 일괄 반영된다.
쿼리 수 상한은 `keyword_loader.py --limit N` (기본 Google News 8개).

## 로컬 실행

```bash
pip install -r requirements.txt
python orchestrator.py --dry-run    # 저장 생략, 출력만 확인
python orchestrator.py              # data/ 저장

# 사이트 개발
cd site && npm install && npm run dev
```
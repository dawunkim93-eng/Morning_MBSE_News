// data/*.json 을 fetch 로 로드하는 훅.
// 빌드 시 publicDir(data/) 가 dist/ 로 복사되므로 런타임 fetch 가 가능하다.
import { useEffect, useState } from 'react'

// 빌드 시점에 data 폴더의 파일 목록을 glob 으로 수집
// (Vite 의 import.meta.glob 은 소스 트리 기준이므로, 파일명은 빌드 시 알 수 없어
//  인덱스 파일을 먼저 읽고 월별 파일을 fetch 하는 2단계 로딩 사용)
const MANIFEST = import.meta.glob('/data/*.json', { eager: true, import: 'default' })

// ── 파일명 기반 분류 ──
function classify() {
  const daily = {}        // YYYY-MM-DD.json → 일일 브리핑
  const newsMonths = []   // news-YYYY-MM.json
  const papersMonths = [] // papers-YYYY-MM.json

  for (const [path, content] of Object.entries(MANIFEST)) {
    const file = path.split('/').pop()
    if (/^\d{4}-\d{2}-\d{2}\.json$/.test(file)) {
      daily[file.replace('.json', '')] = content
    } else if (file.startsWith('news-')) {
      newsMonths.push({ month: file.replace('news-', '').replace('.json', ''), content })
    } else if (file.startsWith('papers-')) {
      papersMonths.push({ month: file.replace('papers-', '').replace('.json', ''), content })
    }
  }
  newsMonths.sort((a, b) => b.month.localeCompare(a.month))
  papersMonths.sort((a, b) => b.month.localeCompare(a.month))
  return { daily, newsMonths, papersMonths }
}

const CLASSIFIED = classify()

// 최신 일일 브리핑 날짜 (파일명 내림차순 첫 번째)
export const LATEST_DATE = Object.keys(CLASSIFIED.daily).sort().pop() ?? null

export function useLatestBriefing() {
  return CLASSIFIED.daily[LATEST_DATE] ?? null
}

export function useArchive() {
  return {
    daily: CLASSIFIED.daily,
    newsMonths: CLASSIFIED.newsMonths,
    papersMonths: CLASSIFIED.papersMonths,
  }
}

// 연도 목록 (필터용)
export function useYears() {
  const { newsMonths, papersMonths } = CLASSIFIED
  const years = new Set()
  for (const { month } of newsMonths) years.add(month.slice(0, 4))
  for (const { month } of papersMonths) years.add(month.slice(0, 4))
  return [...years].sort().reverse()
}
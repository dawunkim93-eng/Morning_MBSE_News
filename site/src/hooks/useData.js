// data/*.json 을 fetch 로 로드하는 훅.
// 빌드 시 closeBundle 훅(vite.config.js)이 data/ 를 dist/data 로 복사하므로
// 런타임에 import.meta.glob('/data/*.json') 매니페스트 키로 fetch 가 가능하다.
import { useEffect, useState } from 'react'

// base 경로 (GitHub Pages 프로젝트 페이지 하위 경로 대응)
const BASE = import.meta.env.BASE_URL // '/Morning_MBSE_News/'

// 빌드 시점에 data 폴더의 파일 목록을 glob 으로 수집
// (import.meta.glob 키는 '/data/xxx.json' 이므로 런타임 fetch 시 base 를 붙인다)
const MANIFEST = import.meta.glob('/data/*.json', { import: 'default' })

// ── 파일명 기반 분류 ──
function classifyPaths() {
  const dailyPaths = {}        // YYYY-MM-DD.json → 일일 브리핑
  const newsMonths = []        // news-YYYY-MM.json
  const papersMonths = []      // papers-YYYY-MM.json

  for (const path of Object.keys(MANIFEST)) {
    const file = path.split('/').pop()
    if (/^\d{4}-\d{2}-\d{2}\.json$/.test(file)) {
      dailyPaths[file.replace('.json', '')] = path
    } else if (file.startsWith('news-')) {
      newsMonths.push({ month: file.replace('news-', '').replace('.json', ''), path })
    } else if (file.startsWith('papers-')) {
      papersMonths.push({ month: file.replace('papers-', '').replace('.json', ''), path })
    }
  }
  newsMonths.sort((a, b) => b.month.localeCompare(a.month))
  papersMonths.sort((a, b) => b.month.localeCompare(a.month))
  return { dailyPaths, newsMonths, papersMonths }
}

const { dailyPaths, newsMonths: NEWS_MONTH_PATHS, papersMonths: PAPER_MONTH_PATHS } = classifyPaths()

// '/data/x.json' → '{BASE}data/x.json' (이중 슬래시 방지)
function resolve(path) {
  return (BASE.endsWith('/') ? BASE : BASE + '/') + path.replace(/^\//, '')
}

async function fetchJson(path) {
  const res = await fetch(resolve(path))
  if (!res.ok) throw new Error(`fetch 실패: ${path} (${res.status})`)
  return res.json()
}

// 최신 일일 브리핑 날짜 (파일명 내림차순 첫 번째)
export const LATEST_DATE = Object.keys(dailyPaths).sort().pop() ?? null

// ── 홈: 오늘의 브리핑 ──
export function useLatestBriefing() {
  const [briefing, setBriefing] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    let alive = true
    async function load() {
      try {
        const data = await fetchJson(dailyPaths[LATEST_DATE])
        if (alive) setBriefing(data)
      } catch (e) {
        if (alive) setError(e)
      } finally {
        if (alive) setLoading(false)
      }
    }
    if (LATEST_DATE) load()
    else setLoading(false)
    return () => { alive = false }
  }, [])

  return { briefing, loading, error }
}

// ── 아카이브: 월별 데이터 전체 로드 ──
export function useArchive() {
  const [data, setData] = useState({ newsMonths: [], papersMonths: [] })
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    let alive = true
    async function load() {
      try {
        // 각 월별 파일을 병렬 fetch
        const [newsPairs, paperPairs] = await Promise.all([
          Promise.all(NEWS_MONTH_PATHS.map(async m => ({
            month: m.month,
            content: await fetchJson(m.path),
          }))),
          Promise.all(PAPER_MONTH_PATHS.map(async m => ({
            month: m.month,
            content: await fetchJson(m.path),
          }))),
        ])
        if (alive) setData({ newsMonths: newsPairs, papersMonths: paperPairs })
      } catch (e) {
        if (alive) setError(e)
      } finally {
        if (alive) setLoading(false)
      }
    }
    load()
    return () => { alive = false }
  }, [])

  return { ...data, loading, error }
}

// 연도 목록 (필터용)
export function useYears() {
  const years = new Set()
  for (const { month } of NEWS_MONTH_PATHS) years.add(month.slice(0, 4))
  for (const { month } of PAPER_MONTH_PATHS) years.add(month.slice(0, 4))
  return [...years].sort().reverse()
}
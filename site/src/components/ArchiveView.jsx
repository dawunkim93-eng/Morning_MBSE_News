import { useMemo, useState, useEffect } from 'react'
import { useArchive, useYears } from '../hooks/useData.js'
import { CATEGORY_LABELS, toISODate } from '../utils/labels.js'
import ItemCard from './ItemCard.jsx'

const CATEGORIES = ['SysML', 'UAF', 'Tool', 'Standard', 'Research', 'Digital', 'Industry']

export default function ArchiveView({ externalQuery = '' } = {}) {
  const { newsMonths, papersMonths, loading, error } = useArchive()
  const years = useYears()

  const [tab, setTab] = useState('news')          // news | papers
  const [category, setCategory] = useState(null)  // null = 전체
  const [year, setYear] = useState(null)          // null = 전체
  const [query, setQuery] = useState(externalQuery)

  // 외부(사이드바 검색바)에서 검색어가 들어오면 동기화
  useEffect(() => {
    if (externalQuery !== '') setQuery(externalQuery)
  }, [externalQuery])

  const months = tab === 'news' ? newsMonths : papersMonths

  // ── 필터링 ──
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return months
      .filter(m => !year || m.month.startsWith(year))
      .map(m => ({
        month: m.month,
        items: (m.content.items ?? []).filter(it => {
          if (category && (it.category || 'Research') !== category) return false
          if (q && !(
            it.title.toLowerCase().includes(q) ||
            (it.summary || '').toLowerCase().includes(q) ||
            (it.abstract || '').toLowerCase().includes(q) ||
            (it.authors || '').toLowerCase().includes(q)
          )) return false
          return true
        }),
      }))
      .filter(m => m.items.length > 0)
  }, [months, year, category, query])

  const totalCount = filtered.reduce((s, m) => s + m.items.length, 0)

  if (loading) {
    return <div className="loading">아카이브 로딩 중…</div>
  }
  if (error) {
    return (
      <div className="empty-state">
        <span className="icon">⚠️</span>
        아카이브 로드 실패: {String(error.message || error)}
      </div>
    )
  }

  return (
    <div>
      {/* ── 아카이브 히어로 (텍스트 전용 — CTA는 뷰포트당 1개 규칙상 없음) ── */}
      <div className="hero-panel" style={{ alignItems: 'stretch', gap: 0 }}>
        <div className="hero-text">
          <h1 className="hero-headline">아카이브</h1>
          <p className="hero-body" style={{ marginBottom: 0 }}>
            뉴스 {newsMonths.reduce((s, m) => s + m.content.count, 0)}건 ·
            논문 {papersMonths.reduce((s, m) => s + m.content.count, 0)}건 ·
            카테고리·연도·키워드로 탐색하세요.
          </p>
        </div>
      </div>

      {/* ── 탭 (고스트 네비 스타일 가로 배치) ── */}
      <div className="sidebar-nav" style={{ flexDirection: 'row', margin: '0 0 16px' }}>
        <button
          className={`nav-item ${tab === 'news' ? 'active' : ''}`}
          onClick={() => setTab('news')}
        >
          <span className="nav-icon">✉</span> 뉴스
        </button>
        <button
          className={`nav-item ${tab === 'papers' ? 'active' : ''}`}
          onClick={() => setTab('papers')}
        >
          <span className="nav-icon">Σ</span> 논문
        </button>
      </div>

      {/* ── 카테고리·연도 필터 ── */}
      <div className="filter-bar">
        <button
          className={`chip ${category === null ? 'active' : ''}`}
          onClick={() => setCategory(null)}
        >
          전체
        </button>
        {Object.entries(CATEGORY_LABELS).map(([key, label]) => (
          <button
            key={key}
            className={`chip ${category === key ? 'active' : ''}`}
            onClick={() => setCategory(category === key ? null : key)}
          >
            {label}
          </button>
        ))}
        <span style={{ width: 1, height: 20, background: 'var(--color-fog)' }} />
        <button
          className={`chip ${year === null ? 'active' : ''}`}
          onClick={() => setYear(null)}
        >
          전체 년도
        </button>
        {years.map(y => (
          <button
            key={y}
            className={`chip mono-label ${year === y ? 'active' : ''}`}
            onClick={() => setYear(year === y ? null : y)}
          >
            {y}
          </button>
        ))}
      </div>

      {/* ── 검색 결과 ── */}
      {totalCount === 0 ? (
        <div className="empty-state">
          <span className="icon">🔍</span>
          조건에 맞는 항목이 없습니다.
        </div>
      ) : (
        filtered.map(({ month, items }) => (
          <div key={month} style={{ marginBottom: 'var(--spacing-32)' }}>
            <h2 className="section-header">
              <span className="section-label mono-label">{month}</span>
              <span className="section-count">{items.length}건</span>
            </h2>
            <div className="cards-grid">
              {items
                .slice()
                .sort((a, b) =>
                  (toISODate(b.date) || '').localeCompare(toISODate(a.date) || '') ||
                  (b.score ?? 0) - (a.score ?? 0))
                .map(item => (
                  <ItemCard key={item.url} item={item} />
                ))}
            </div>
          </div>
        ))
      )}
    </div>
  )
}
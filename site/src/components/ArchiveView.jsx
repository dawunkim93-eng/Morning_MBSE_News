import { useMemo, useState } from 'react'
import { useArchive, useYears } from '../hooks/useData.js'
import { CATEGORY_LABELS, toISODate } from '../utils/labels.js'
import ItemCard from './ItemCard.jsx'

const CATEGORIES = ['SysML', 'UAF', 'Tool', 'Standard', 'Research', 'Digital', 'Industry']

export default function ArchiveView({ externalQuery = '' } = {}) {
  const { newsMonths, papersMonths } = useArchive()
  const years = useYears()

  const [tab, setTab] = useState('news')          // news | papers
  const [category, setCategory] = useState(null)  // null = 전체
  const [year, setYear] = useState(null)          // null = 전체
  const [query, setQuery] = useState(externalQuery)          // 텍스트 검색

  const months = tab === 'news' ? newsMonths : papersMonths

  // ── 필터링 ──
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return months
      .filter(m => !year || m.month.startsWith(year))
      .map(m => ({
        month: m.month,
        items: m.content.items.filter(it => {
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

  return (
    <div>
      <div className="hero" style={{ paddingBottom: 8 }}>
        <h1 className="hero-title">아카이브</h1>
        <div className="hero-date">
          뉴스 {newsMonths.reduce((s, m) => s + m.content.count, 0)}건 ·
          논문 {papersMonths.reduce((s, m) => s + m.content.count, 0)}건
        </div>
      </div>

      {/* ── 탭 ── */}
      <div className="nav-tabs" style={{ margin: '0 0 4px' }}>
        <button
          className={`nav-tab ${tab === 'news' ? 'active' : ''}`}
          onClick={() => setTab('news')}
        >
          뉴스
        </button>
        <button
          className={`nav-tab ${tab === 'papers' ? 'active' : ''}`}
          onClick={() => setTab('papers')}
        >
          논문
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
        <span style={{ width: 1, height: 20, background: 'var(--border)' }} />
        <button
          className={`chip ${year === null ? 'active' : ''}`}
          onClick={() => setYear(null)}
        >
          전체 년도
        </button>
        {years.map(y => (
          <button
            key={y}
            className={`chip mono ${year === y ? 'active' : ''}`}
            onClick={() => setYear(year === y ? null : y)}
          >
            {y}
          </button>
        ))}
      </div>

      {/* ── 검색 결과 ── */}
      {totalCount === 0 ? (
        <div className="empty-state">
          <div className="icon">🔍</div>
          조건에 맞는 항목이 없습니다.
        </div>
      ) : (
        filtered.map(({ month, items }) => (
          <div key={month}>
            <h2 className="section-title mono">
              {month} <span className="count">{items.length}건</span>
            </h2>
            <div className="cards-grid">
              {items
                .slice()
                .sort((a, b) => toISODate(b.date).localeCompare(toISODate(a.date)) || (b.score ?? 0) - (a.score ?? 0))
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
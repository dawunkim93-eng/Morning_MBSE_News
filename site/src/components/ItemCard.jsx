import { useState } from 'react'
import {
  CATEGORY_LABELS,
  SOURCE_LABELS,
  formatDate, toISODate,
} from '../utils/labels.js'
import { CATEGORY_GLYPH } from '../utils/badges.js'

export default function ItemCard({ item, showTodayFlag = false }) {
  const [expanded, setExpanded] = useState(false)

  const category = item.category || 'Research'
  const source = item.source || 'news'
  const date = toISODate(item.date)
  const hasSummary = item.source === 'arxiv'
    ? Boolean(item.abstract)
    : Boolean(item.summary)
  const bodyText = item.source === 'arxiv'
    ? (item.abstract || '')
    : (item.summary || item.abstract || '')

  // 출처 라벨 — OMG/arXiv는 공식 발신처로 강조
  const srcLabel = SOURCE_LABELS[source] ?? source
  const isOfficial = source === 'omg_press'
  const isPaper = item.source === 'arxiv' || item.source === 'semantic'

  // 썸네일 글리프 — 카테고리 첫 글자 (공식 소스는 OMG 'Ω'/arXiv 'Σ')
  const glyph = source === 'omg_press' ? 'Ω'
    : source === 'incose_site' ? '◇'
    : isPaper ? 'Σ'
    : (CATEGORY_GLYPH[category] || 'M')

  const thumbClass =
    source === 'omg_press' || source === 'incose_site'
      ? 'card-thumb thumb-omg'
      : isPaper
        ? 'card-thumb'
        : 'card-thumb'

  const scoreHigh = (item.score ?? 0) >= 15

  return (
    <article className="item-card">
      {/* ── 48px 썸네일 타일 (카테고리 글리프) ── */}
      <div className={`card-thumb`} aria-hidden="true">{glyph}</div>

      <div className="card-main">
        {/* 아이덴티티 행: 출처 · 날짜 (+TODAY/참고 플래그) */}
        <div className="card-byline">
          <span className="src-name">{SOURCE_LABELS[source] ?? source}</span>
          <span className="dot" />
          <span>{formatDate(date) || '날짜 미상'}</span>
          {showTodayFlag && (
            item.is_today
              ? <span className="flag flag-today">Today</span>
              : <span className="flag flag-fallback">참고</span>
          )}
        </div>

        {/* 헤드라인 18px/600 */}
        <h3 className="card-title">
          <a href={item.url} target="_blank" rel="noopener noreferrer">
            {item.title}
          </a>
        </h3>

        {/* 요약/초록 — 3줄 클램프, 클릭 전개 */}
        {hasSummary && (
          <div className={`card-body ${expanded ? 'expanded' : ''}`}>
            <div
              className="card-text"
              onClick={() => setExpanded(e => !e)}
            >
              {bodyText}
            </div>
            {!expanded && <div className="expand-hint">클릭하여 전체 보기 ▾</div>}
          </div>
        )}

        {/* 저자 (논문) */}
        {item.authors && (
          <div className="card-authors">{item.authors}</div>
        )}

        {/* 인터랙션 행: 카테고리 배지 · 점수 */}
        <div className="card-meta">
          <span
            className={`cat-badge ${
              isOfficial ? 'cat-featured' : 'cat-neutral'
            }`}
          >
            {CATEGORY_LABELS[category] ?? category}
          </span>
          {item.score != null && (
            <span className={`score-pill ${scoreHigh ? 'high' : ''}`}>
              score {item.score}
            </span>
          )}
        </div>
      </div>
    </article>
  )
}
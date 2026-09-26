import { useState } from 'react'
import {
  CATEGORY_LABELS, CATEGORY_CLASS,
  SOURCE_LABELS, SOURCE_CLASS,
  formatDate, toISODate,
} from '../utils/labels.js'
import { sourceIcon } from '../utils/icons.js'

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

  const scoreHigh = (item.score ?? 0) >= 15

  return (
    <article className="item-card">
      <div className="card-header">
        <span className={`cat-tag ${CATEGORY_CLASS[category] ?? 'cat-research'}`}>
          {CATEGORY_LABELS[category] ?? category}
        </span>
        <span className={`src-badge ${SOURCE_CLASS[source] ?? 'src-news'}`}>
          {sourceIcon(source)} {SOURCE_LABELS[source] ?? source}
        </span>
        {showTodayFlag && (
          item.is_today
            ? <span className="today-flag">TODAY</span>
            : <span className="fallback-flag">참고</span>
        )}
      </div>

      <h3 className="card-title">
        <a href={item.url} target="_blank" rel="noopener noreferrer">
          {item.title}
        </a>
      </h3>

      {item.authors && (
        <div className="mono" style={{ color: 'var(--text-secondary)', fontSize: '12px' }}>
          {item.authors}
        </div>
      )}

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

      <div className="card-footer">
        <span className="card-date mono">{formatDate(date) || '날짜 미상'}</span>
        {item.score != null && (
          <span className={`card-score mono ${item.score >= 10 ? 'high' : ''}`}>
            점수 {item.score}
          </span>
        )}
      </div>
    </article>
  )
}
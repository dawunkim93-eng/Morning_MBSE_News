// RankList — AI Times "Most Popular" 스타일
// 숫자 순위 + 제목만 (이미지·요약 없는 순위형 텍스트 리스트)
import { toISODate } from '../utils/labels.js'

export default function RankList({ items, rankLabel = 'Popular' }) {
  if (!items?.length) {
    return (
      <div className="empty-state headline-empty">
        순위를 매길 항목이 없습니다.
      </div>
    )
  }

  return (
    <ol className="rank-list">
      {items.map((item, idx) => (
        <li key={item.url} className="rank-item">
          <span className="rank-number" aria-hidden="true">{idx + 1}</span>
          <a
            href={item.url}
            target="_blank"
            rel="noopener noreferrer"
            className="rank-link"
          >
            <span className="rank-title">{item.title}</span>
            <span className="rank-meta">
              <span className="score-pill">
                score {item.score ?? 0}
              </span>
              <span className="rank-date">{toISODate(item.date)}</span>
            </span>
          </a>
        </li>
      ))}
    </ol>
  )
}
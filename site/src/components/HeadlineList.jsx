// HeadlineList — AI Times "Headlines" 스타일
// 제목 + 출처 라벨만 세로 리스트 (요약·날짜 없음)
import { SOURCE_LABELS, toISODate } from '../utils/labels.js'

export default function HeadlineList({ items }) {
  if (!items?.length) {
    return (
      <div className="empty-state headline-empty">
        오늘의 헤드라인이 없습니다.
      </div>
    )
  }

  return (
    <ul className="headline-list">
      {items.map(item => (
        <li key={item.url} className="headline-item">
          <a
            href={item.url}
            target="_blank"
            rel="noopener noreferrer"
            className="headline-link"
          >
            <span className="headline-title">{item.title}</span>
            <span className="headline-meta">
              {SOURCE_LABELS[item.source] ?? item.source}
            </span>
          </a>
        </li>
      ))}
    </ul>
  )
}
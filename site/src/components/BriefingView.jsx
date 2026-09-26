import { LATEST_DATE } from '../hooks/useData.js'
import { formatDate } from '../utils/labels.js'
import ItemCard from './ItemCard.jsx'

export default function BriefingView({ briefing }) {
  if (!briefing) {
    return (
      <div className="empty-state">
        <div className="icon">📡</div>
        아직 브리핑 데이터가 없습니다.
      </div>
    )
  }

  const news = briefing.news ?? []
  const papers = briefing.papers ?? []
  const todayNews = news.filter(i => i.is_today)
  const refNews = news.filter(i => !i.is_today)
  const todayPapers = papers.filter(i => i.is_today)
  const refPapers = papers.filter(i => !i.is_today)

  return (
    <div>
      <div className="hero">
        <h1 className="hero-title">오늘의 브리핑</h1>
        <div className="hero-date">
          {briefing.report_date_kr}
          {briefing.window_start_kst && ` · 수집 범위 ${briefing.window_start_kst} 07:00 ~ ${briefing.window_end_kst} 07:00 KST`}
        </div>
        <div className="hero-meta mono">
          <span>뉴스 {todayNews.length}건</span>
          <span>논문 {todayPapers.length}건</span>
          <span>생성 {briefing.generated_at?.slice(0, 16).replace('T', ' ') ?? ''}</span>
        </div>
      </div>

      {/* ── 오늘의 뉴스 ── */}
      <h2 className="section-title">
        📰 뉴스 <span className="count">{todayNews.length}건</span>
      </h2>
      {todayNews.length > 0 ? (
        <div className="cards-grid">
          {todayNews.map(item => (
            <ItemCard key={item.url} item={item} showTodayFlag />
          ))}
        </div>
      ) : (
        <div className="empty-state">
          <div className="icon">🌙</div>
          수집 범위 내 새 뉴스가 없습니다.
        </div>
      )}

      {/* ── 오늘의 논문 ── */}
      <h2 className="section-title">
        📄 신규 논문 <span className="count">{todayPapers.length}건</span>
      </h2>
      {todayPapers.length > 0 ? (
        <div className="cards-grid">
          {todayPapers.map(item => (
            <ItemCard key={item.url} item={item} showTodayFlag />
          ))}
        </div>
      ) : (
        <div className="empty-state">
          <div className="icon">📚</div>
          수집 범위 내 신규 논문이 없습니다.
        </div>
      )}

      {/* ── 참고: 폴백 항목 ── */}
      {(refNews.length > 0 || refPapers.length > 0) && (
        <>
          <h2 className="section-title">
            🗂 참고 — 최근 주목할 만한 소식 <span className="count">범위 밖</span>
          </h2>
          <div className="cards-grid">
            {refNews.map(item => (
              <ItemCard key={item.url} item={item} showTodayFlag />
            ))}
            {refPapers.map(item => (
              <ItemCard key={item.url} item={item} showTodayFlag />
            ))}
          </div>
        </>
      )}
    </div>
  )
}
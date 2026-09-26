import { LATEST_DATE } from '../hooks/useData.js'
import { formatDate } from '../utils/labels.js'
import { HeroIllustration } from './HeroIllustration.jsx'
import ItemCard from './ItemCard.jsx'

export default function BriefingView({ onNavigate }) {
  const { briefing, loading, error } = useLatestBriefing()

  if (loading) {
    return (
      <div className="loading">
        브리핑 로딩 중…
      </div>
    )
  }
  if (error) {
    return (
      <div className="empty-state">
        <span className="icon">⚠️</span>
        브리핑 로드 실패: {String(error.message || error)}
      </div>
    )
  }
  if (!briefing) {
    return (
      <div className="empty-state">
        <span className="icon">📡</span>
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
      {/* ── 히어로 패널 (뷰포트당 유일한 블루 CTA) ── */}
      <section className="hero-panel">
        <div className="hero-text">
          <h1 className="hero-headline">오늘의 브리핑</h1>
          <p className="hero-body">
            {briefing.report_date_kr} 발행 · 수집 범위{' '}
            {briefing.window_start_kst} ~ {briefing.window_end_kst} KST.
            뉴스 {todayNews.length}건, 논문 {todayPapers.length}건.
          </p>
          <button className="btn-primary" onClick={() => onNavigate?.('archive')}>
            전체 아카이브 보기 →
          </button>
        </div>
        <HeroIllustration />
      </section>

      {/* ── 뉴스 섹션 ── */}
      <section>
        <h2 className="section-header">
          <span className="section-label">News</span>
          <span className="section-count">{todayNews.length}건</span>
        </h2>
        {todayNews.length > 0 ? (
          <div className="cards-grid">
            {todayNews.map(item => (
              <ItemCard key={item.url} item={item} showTodayFlag />
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <span className="icon">🌙</span>
            수집 범위 내 새 뉴스가 없습니다.
          </div>
        )}
      </section>

      {/* ── 논문 섹션 ── */}
      <section>
        <h2 className="section-header">
          <span className="section-label">Papers</span>
          <span className="section-count">{todayPapers.length}건</span>
        </h2>
        {todayPapers.length > 0 ? (
          <div className="cards-grid">
            {todayPapers.map(item => (
              <ItemCard key={item.url} item={item} showTodayFlag />
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <span className="icon">📚</span>
            수집 범위 내 신규 논문이 없습니다.
          </div>
        )}
      </section>

      {/* ── 참고: 폴백 항목 ── */}
      {(refNews.length > 0 || refPapers.length > 0) && (
        <section>
          <h2 className="section-header">
            <span className="section-label" style={{ color: 'var(--color-slate)' }}>
              Archive Picks
            </span>
            <span className="section-count">범위 밖 참고 항목</span>
          </h2>
          <div className="cards-grid">
            {refNews.map(item => (
              <ItemCard key={item.url} item={item} showTodayFlag />
            ))}
            {refPapers.map(item => (
              <ItemCard key={item.url} item={item} showTodayFlag />
            ))}
          </div>
        </section>
      )}
    </div>
  )
}
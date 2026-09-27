// BriefingView — AI Times 5계층 구성 (Hashnode 디자인 토큰 유지)
//
// ① 톱기사 히어로   : 오늘 항목 중 점수 최고 1건 대형 카드 (오늘 0건 시 참고 폴백)
// ② Headlines(우측) : 오늘 뉴스 제목 리스트
// ③ Latest(좌측)    : 톱기사 제외 뉴스 전체, 1열 세로 타임라인 + 아카이브 더보기
// ④ Popular(우측)   : 오늘 항목 점수 순위 (score desc → date desc)
// ⑤ 논문 섹션(좌측) : 세로 타임라인
//
// 정렬 2차 기준: score desc → date desc (동점 처리)
import { useLatestBriefing } from '../hooks/useData.js'
import { SOURCE_LABELS, CATEGORY_LABELS, formatDate, toISODate } from '../utils/labels.js'
import { CATEGORY_GLYPH } from '../utils/badges.js'
import ItemCard from './ItemCard.jsx'
import HeadlineList from './HeadlineList.jsx'
import RankList from './RankList.jsx'

// 순위 정렬: score 내림차순 → date 내림차순 (동점 처리)
function byRank(a, b) {
  const s = (b.score ?? 0) - (a.score ?? 0)
  if (s !== 0) return s
  return (toISODate(b.date) || '').localeCompare(toISODate(a.date) || '')
}

export default function BriefingView({ onNavigate }) {
  const { briefing, loading, error } = useLatestBriefing()

  if (loading) {
    return <div className="loading">브리핑 로딩 중…</div>
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

  // ── 폴백: 오늘 항목이 없으면 전체(참고 포함) 사용 ──
  const todayNews = news.filter(i => i.is_today)
  const todayPapers = papers.filter(i => i.is_today)
  const hasToday = todayNews.length + todayPapers.length > 0

  const poolNews = hasToday ? todayNews : news
  const poolPapers = hasToday ? todayPapers : papers
  const poolLabel = hasToday ? '오늘' : '최근'

  // ── ① 톱기사: 점수 최고 1건 (뉴스 우선, 없으면 논문) ──
  const allPool = [...poolNews, ...poolPapers].sort(byRank)
  const topStory = allPool[0] ?? null

  // ── ② Headlines: 톱기사 제외 뉴스 ──
  const headlineItems = poolNews.filter(i => i.url !== topStory?.url)

  // ── ④ Popular: 톱기사 포함 전체 점수순 최대 8건 ──
  const rankItems = allPool.slice(0, 8)

  // ── ③ Latest: 톱기사 제외 뉴스 타임라인 ──
  const latestNews = poolNews.filter(i => i.url !== topStory?.url)
  const refNews = hasToday ? news.filter(i => !i.is_today) : []

  return (
    <div>
      {/* ── 발행 라인 (AI Times 발행일 관습) ── */}
      <div className="issue-line">
        <span className="issue-label mono-label">daily briefing</span>
        <span className="issue-date">
          {briefing.report_date_kr} 발행 · 수집 범위{' '}
          {briefing.window_start_kst} ~ {briefing.window_end_kst} KST
        </span>
      </div>

      {!topStory ? (
        <div className="empty-state">
          <span className="icon">📡</span>
          아직 브리핑 항목이 없습니다.
        </div>
      ) : (
        /* ── 2단 본문: 좌(톱기사+Latest+논문) / 우(Headlines+Popular) ── */
        <div className="content-2col">
          {/* ── 좌측 메인 피드 ── */}
          <div className="main-feed">
            {/* ① 톱기사 히어로 */}
            <article className="top-story">
              <div className="top-story-head">
                <div className="card-thumb top-thumb" aria-hidden="true">
                  {topStory.source === 'omg_press' ? 'Ω'
                    : topStory.source === 'incose_site' ? '◇'
                    : (topStory.source === 'arxiv' || topStory.source === 'semantic') ? 'Σ'
                    : (CATEGORY_GLYPH[topStory.category] || 'M')}
                </div>
                <div className="top-story-byline">
                  <span className="flag flag-today">{poolLabel}</span>
                  <span className="src-name">{SOURCE_LABELS[topStory.source] ?? topStory.source}</span>
                  <span className="dot" />
                  <span>{formatDate(toISODate(topStory.date)) || '날짜 미상'}</span>
                </div>
              </div>
              <h2 className="top-story-title">
                <a href={topStory.url} target="_blank" rel="noopener noreferrer">
                  {topStory.title}
                </a>
              </h2>
              {(topStory.summary || topStory.abstract) && (
                <p className="top-story-body">
                  {topStory.source === 'arxiv'
                    ? (topStory.abstract || '').slice(0, 220) + '…'
                    : (topStory.summary || topStory.abstract || '')}
                </p>
              )}
              <div className="top-story-meta">
                <span className="cat-badge cat-featured">
                  {CATEGORY_LABELS[topStory.category] ?? topStory.category}
                </span>
                <span className="score-pill">score {topStory.score ?? 0}</span>
                <a
                  className="top-story-link"
                  href={topStory.url}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  원문 보기 →
                </a>
              </div>
            </article>

            {/* ③ Latest News — 세로 타임라인 */}
            <section>
              <h2 className="section-header">
                <span className="section-label">Latest</span>
                <span className="section-count">{poolLabel} 뉴스 {latestNews.length}건</span>
              </h2>
              {latestNews.length > 0 ? (
                <div className="timeline-feed">
                  {latestNews.map(item => (
                    <ItemCard key={item.url} item={item} showTodayFlag />
                  ))}
                </div>
              ) : (
                <div className="empty-state">
                  <span className="icon">🌙</span>
                  표시할 뉴스가 없습니다.
                </div>
              )}
              {refNews.length > 0 && (
                <div className="more-row">
                  <button className="link-more" onClick={() => onNavigate?.('archive')}>
                    아카이브에서 더 보기 →
                  </button>
                </div>
              )}
            </section>

            {/* ⑤ 논문 섹션 */}
            <section>
              <h2 className="section-header">
                <span className="section-label">Papers</span>
                <span className="section-count">{poolLabel} 논문 {poolPapers.length}건</span>
              </h2>
              {poolPapers.length > 0 ? (
                <div className="timeline-feed">
                  {poolPapers.map(item => (
                    <ItemCard key={item.url} item={item} showTodayFlag />
                  ))}
                </div>
              ) : (
                <div className="empty-state">
                  <span className="icon">📚</span>
                  표시할 논문이 없습니다.
                </div>
              )}
            </section>
          </div>

          {/* ── 우측 사이드: Headlines + Popular ── */}
          <aside className="side-feed">
            <section className="side-block">
              <h2 className="section-header">
                <span className="section-label">Headlines</span>
                <span className="section-count">{headlineItems.length}건</span>
              </h2>
              <HeadlineList items={headlineItems} />
            </section>

            <section className="side-block">
              <h2 className="section-header">
                <span className="section-label">{rankLabel || 'Popular'}</span>
                <span className="section-count">{poolLabel} 항목 점수순</span>
              </h2>
              <RankList items={rankItems} />
            </section>
          </aside>
        </div>
      )}
    </div>
  )
}
import { useState, useEffect } from 'react'
import { HeroIllustration } from './components/HeroIllustration.jsx'
import BriefingView from './components/BriefingView.jsx'
import ArchiveView from './components/ArchiveView.jsx'

// 해시 라우팅: #archive → 아카이브, 그 외 → 홈
function currentRoute() {
  return window.location.hash === '#archive' ? 'archive' : 'home'
}

export default function App() {
  const [route, setRoute] = useState(currentRoute)
  const [query, setQuery] = useState('')

  useEffect(() => {
    const onHash = () => setRoute(currentRoute())
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  const go = (r) => {
    window.location.hash = r === 'archive' ? '#archive' : ''
    setRoute(r)
  }

  return (
    <div className="app-shell">
      {/* ── 좌측 사이드바 ── */}
      <aside className="sidebar">
        <div className="brand" onClick={() => go('home')}>
          <img className="brand-logo" src="/Morning_MBSE_News/favicon.svg" alt="" />
          <span className="brand-name">
            MBSE <span className="accent">Letters</span>
          </span>
        </div>

        <div className="search-box">
          <span className="search-icon">⌕</span>
          <input
            className="search-input"
            placeholder="검색…"
            value={query}
            onChange={e => {
              setQuery(e.target.value)
              // 검색 입력 시 자동으로 아카이브로 전환
              if (e.target.value && route !== 'archive') go('archive')
            }}
          />
        </div>

        <nav className="sidebar-nav">
          <button
            className={`nav-item ${route === 'home' ? 'active' : ''}`}
            onClick={() => go('home')}
          >
            <span className="nav-icon">✉</span> 브리핑
          </button>
          <button
            className={`nav-item ${route === 'archive' ? 'active' : ''}`}
            onClick={() => go('archive')}
          >
            <span className="nav-icon">▤</span> 아카이브
          </button>
        </nav>

        <div className="announcement">
          <p className="announcement-title">매일 아침 07:00 KST</p>
          <p className="announcement-body">
            GitHub Actions가 MBSE 뉴스·논문을 수집·요약해
            이 아카이브에 자동 발행합니다.{' '}
            <a
              href="https://github.com/dawunkim93-eng/Morning_MBSE_News"
              target="_blank"
              rel="noopener noreferrer"
            >
              파이프라인 보기
            </a>
          </p>
        </div>

        <div className="sidebar-footer mono-label">
          powered by github actions
        </div>
      </aside>

      {/* ── 메인 컬럼 ── */}
      <main className="main-col">
        <div className="main-inner">
          {route === 'home'
            ? <BriefingView onNavigate={go} />
            : <ArchiveView externalQuery={query} />}
        </div>
        <footer className="site-footer" style={{ margin: '0 var(--spacing-32)' }}>
          <div>MBSE Letters — 매일 오전 07:00 KST 자동 수집</div>
          <div>Powered by GitHub Actions · arXiv · Google News · OMG · Bing</div>
        </footer>
      </main>
    </div>
  )
}
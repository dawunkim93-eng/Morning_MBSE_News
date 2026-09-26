import { useState, useEffect } from 'react'
import { useLatestBriefing, LATEST_DATE } from './hooks/useData.js'
import { formatDate } from './utils/labels.js'
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

  const briefing = useLatestBriefing()

  const go = (r) => {
    window.location.hash = r === 'archive' ? '#archive' : ''
    setRoute(r)
  }

  return (
    <>
      <header className="site-header">
        <div className="header-inner">
          <div className="brand" onClick={() => go('home')}>
            <img className="brand-logo" src="/favicon.svg" alt="" />
            <span className="brand-name">
              MBSE <span className="accent">Letters</span>
            </span>
            <span className="brand-tagline">매일 아침의 시스템 엔지니어링 브리핑</span>
          </div>

          <div className="search-box">
            <span className="search-icon">⌕</span>
            <input
              className="search-input"
              placeholder="제목·요약·저자 검색…"
              value={query}
              onChange={e => {
                setQuery(e.target.value)
                // 검색 입력 시 자동으로 아카이브로 전환
                if (e.target.value && route !== 'archive') go('archive')
              }}
            />
          </div>

          <nav className="nav-tabs">
            <button
              className={`nav-tab ${route === 'home' ? 'active' : ''}`}
              onClick={() => go('home')}
            >
              브리핑
            </button>
            <button
              className={`nav-tab ${route === 'archive' ? 'active' : ''}`}
              onClick={() => go('archive')}
            >
              아카이브
            </button>
          </nav>
        </div>
      </header>

      <main className="container">
        {route === 'home'
          ? <BriefingView briefing={briefing} />
          : <ArchiveView  />}
      </main>

      <footer className="site-footer">
        <div>
          MBSE Letters — 매일 오전 07:00 KST 자동 수집 ·
          데이터 {LATEST_DATE ? `최신 ${formatDate(LATEST_DATE)}` : '없음'}
        </div>
        <div style={{ marginTop: 4 }}>
          Powered by GitHub Actions · arXiv · Google News · OMG
        </div>
      </footer>
    </>
  )
}
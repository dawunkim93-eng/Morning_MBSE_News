// 히어로 패널 우측 일러스트 — MBSE 블록 다이어그램 모티프
// 평면 2색 (Blueprint Blue + Mint), 그라디언트 없음, 14px radius
export function HeroIllustration() {
  return (
    <svg
      className="hero-illustration"
      viewBox="0 0 220 180"
      role="img"
      aria-label="MBSE 블록 다이어그램 일러스트"
    >
      {/* ── 상위 시스템 블록 ── */}
      <rect x="30" y="18" width="160" height="34" rx="6"
            fill="none" stroke="#1d52de" strokeWidth="2" />
      <text x="110" y="39" textAnchor="middle"
            fill="#1d52de" fontSize="11" fontWeight="600"
            fontFamily="Inter, sans-serif">System of Interest</text>

      {/* ── 커넥터 (상위 → 하위 블록) ── */}
      <line x1="70" y1="52" x2="70" y2="78" stroke="#d1d4d9" strokeWidth="2" />
      <path d="M66 73 L70 79 L74 73" fill="none" stroke="#d1d4d9" strokeWidth="2" />
      <line x1="150" y1="52" x2="150" y2="78" stroke="#d1d4d9" strokeWidth="2" />
      <path d="M146 73 L150 79 L154 73" fill="none" stroke="#d1d4d9" strokeWidth="2" />

      {/* ── 2층 블록들 ── */}
      <rect x="20" y="80" width="100" height="34" rx="6"
            fill="#1d52de" />
      <text x="70" y="101" textAnchor="middle" fill="#fff"
            fontSize="11" fontWeight="600" fontFamily="Inter, sans-serif">Requirements</text>

      <rect x="130" y="80" width="80" height="34" rx="6"
            fill="none" stroke="#00bc7d" strokeWidth="2" />
      <text x="170" y="101" textAnchor="middle" fill="#00bc7d"
            fontSize="10" fontWeight="600" fontFamily="Inter, sans-serif">Analysis</text>

      {/* ── 커넥터 (2층 → 3층) ── */}
      <line x1="70" y1="114" x2="70" y2="140" stroke="#d1d4d9" strokeWidth="2" />
      <path d="M66 135 L70 141 L74 135" fill="none" stroke="#d1d4d9" strokeWidth="2" />
      <line x1="170" y1="114" x2="112" y2="140" stroke="#d1d4d9" strokeWidth="2"
            strokeDasharray="4 3" />
      <path d="M108 135 L112 141 L116 135" fill="none" stroke="#d1d4d9" strokeWidth="2" />

      {/* ── 3층 블록 ── */}
      <rect x="50" y="142" width="120" height="34" rx="6"
            fill="none" stroke="#1d52de" strokeWidth="2" strokeDasharray="6 3" />
      <text x="110" y="163" textAnchor="middle"
            fill="#1d52de" fontSize="11" fontWeight="600"
            fontFamily="Inter, sans-serif">Architecture</text>
    </svg>
  )
}
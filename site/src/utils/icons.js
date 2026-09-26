// 출처 → 표시 아이콘/이니셜 매핑
export function sourceIcon(source) {
  switch (source) {
    case 'omg_press':   return '◆'
    case 'incose_site': return '◇'
    case 'arxiv':
    case 'semantic':    return 'Σ'
    default:            return '📰'
  }
}
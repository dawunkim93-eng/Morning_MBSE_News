// 카테고리·출처 표기 유틸
export const CATEGORY_LABELS = {
  'SysML':    'SysML',
  'UAF':      'UAF',
  'Tool':     '도구',
  'Standard': '표준',
  'Research': '연구',
  'Digital':  '디지털 엔지니어링',
  'Industry': '산업',
}

export const CATEGORY_CLASS = {
  'SysML':    'cat-sysml',
  'UAF':      'cat-uaf',
  'Tool':     'cat-tool',
  'Standard': 'cat-standard',
  'Research': 'cat-research',
  'Digital':  'cat-digital',
  'Industry': 'cat-industry',
}

export const SOURCE_LABELS = {
  'omg_press':  'OMG 공식',
  'incose_site':'INCOSE',
  'arxiv':      'arXiv',
  'semantic':   'Semantic Scholar',
  'news':       '뉴스',
}

export const SOURCE_CLASS = {
  'omg_press':   'src-omg',
  'incose_site': 'src-incose',
  'arxiv':       'src-arxiv',
  'semantic':    'src-arxiv',
  'news':        'src-news',
}

// YYYY-MM-DD → "2025년 7월 21일"
export function formatDate(s) {
  if (!s) return ''
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (m) return `${m[1]}년 ${parseInt(m[2])}월 ${parseInt(m[3])}일`
  return s
}

// RFC822 날짜 → YYYY-MM-DD
export function toISODate(s) {
  if (!s) return ''
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10)
  try {
    const d = new Date(s)
    if (isNaN(d)) return s
    return d.toISOString().slice(0, 10)
  } catch {
    return s
  }
}
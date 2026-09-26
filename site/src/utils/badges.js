// 출처 → 라벨/썸네일 매핑
export const SOURCE_LABELS = {
  'omg_press':  'OMG 공식',
  'incose_site':'INCOSE',
  'arxiv':      'arXiv',
  'semantic':   'Semantic Scholar',
  'news':       '뉴스',
}

// 썸네일 타일 글리프 — 카테고리 첫 글자 (48px 타일에 표시)
export const CATEGORY_GLYPH = {
  'SysML':    'S',
  'UAF':      'U',
  'Tool':     'T',
  'Standard': '§',   // 표준 기호
  'Research': 'R',
  'Digital':  'D',
  'Industry': 'I',
}

// 카테고리가 강조 대상인지 판정 — 모든 카테고리는 균등하게 중립(슬레이트),
// 항목 자체의 점수(>=15)일 때만 블루로 강조하는 대신,
// 블루는 TODAY 플래그와 OMG 공식/arXiv 등 "공식 발신처"에 사용한다.
export function categoryIsFeatured(category, source) {
  return source === 'omg_press' || source === 'arxiv'
}
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// GitHub Pages 프로젝트 페이지는 /Morning_MBSE_News/ 하위 경로에 서빙되므로
// base 를 레포명으로 설정해야 정적 에셋 경로가 올바르게 해석된다.
export default defineConfig({
  base: '/Morning_MBSE_News/',
  plugins: [react()],
  build: {
    outDir: 'dist',
  },
  // data/*.json 을 빌드 시 정적 에셋으로 복사 (fetch 로 로드)
  publicDir: 'data',
})
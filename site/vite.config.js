import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { cpSync, existsSync, mkdirSync } from 'fs'

// GitHub Pages 프로젝트 페이지는 /Morning_MBSE_News/ 하위 경로에 서빙되므로
// base 를 레포명으로 설정해야 정적 에셋 경로가 올바르게 해석된다.
export default defineConfig({
  base: '/Morning_MBSE_News/',
  plugins: [
    react(),
    // data/*.json 을 dist 로 복사 (fetch 로 로드)
    {
      name: 'copy-data',
      apply: 'build',
      closeBundle() {
        cpSync(new URL('./data', import.meta.url).pathname,
               new URL('./dist/data', import.meta.url).pathname,
               { recursive: true })
      },
    },
  ],
  build: {
    outDir: 'dist',
  },
  // public/ (favicon 등) 은 Vite 기본 publicDir 그대로 사용
})
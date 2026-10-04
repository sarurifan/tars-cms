import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { resolve } from 'path'

export default defineConfig({
  plugins: [vue()],
  // admin 部署在 CmsWeb 的 /admin/ 子路径下，必须设置 base，
  // 否则产物会引用根路径 /assets/* 而被网关的 / 路由（h5）抢走 → 白屏
  base: '/admin/',
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src')
    }
  },
  server: {
    port: 5174,
    host: '0.0.0.0',
    proxy: {
      '/api': {
        target: 'http://192.168.1.95:8200',
        changeOrigin: true,
        headers: { Host: 'cms' }
      }
    }
  },
  build: {
    outDir: 'dist',
    chunkSizeWarningLimit: 1500
  }
})

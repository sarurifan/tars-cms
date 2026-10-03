import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { resolve } from 'path'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src')
    }
  },
  server: {
    port: 5173,
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
    chunkSizeWarningLimit: 1000
  }
})

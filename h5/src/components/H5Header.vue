<template>
  <header class="h5-header">
    <div class="header-inner">
      <!-- Logo -->
      <router-link to="/" class="header-logo">
        <img src="/logo.png" alt="tars-cms" class="logo-img" />
      </router-link>

      <!-- 主导航 -->
      <nav class="header-nav">
        <router-link to="/" class="nav-link" :class="{ active: isActive('/') }">首页</router-link>
        <router-link
          v-for="c in topCategories"
          :key="c.id"
          :to="`/category/${c.slug || c.id}`"
          class="nav-link"
          :class="{ active: isActive(`/category/${c.slug || c.id}`) }"
        >
          {{ c.name }}
        </router-link>
      </nav>

      <!-- 右侧 -->
      <div class="header-right">
        <button class="theme-toggle" @click="toggleTheme" :title="theme === 'red' ? '切换为蓝色主题' : '切换为红色主题'">
          <span class="theme-dot" :class="theme === 'red' ? 'dot-red' : 'dot-blue'"></span>
          <span class="theme-label">{{ theme === 'red' ? '红' : '蓝' }}</span>
        </button>
        <template v-if="isLogin">
          <span class="user-chip">{{ nickname }}</span>
          <button class="btn-logout" @click="handleLogout">退出</button>
        </template>
        <template v-else>
          <router-link to="/login" class="btn-login">登录</router-link>
        </template>
      </div>
    </div>
  </header>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getCategories, logout } from '@/api/content'

const route = useRoute()
const router = useRouter()
const topCategories = ref<any[]>([])

const isLogin = ref(!!localStorage.getItem('h5_token'))
const theme = ref(localStorage.getItem('h5_theme') || 'red')

function applyTheme(t: string) {
  document.documentElement.setAttribute('data-theme', t === 'blue' ? 'blue' : 'red')
  localStorage.setItem('h5_theme', t)
}
function toggleTheme() {
  theme.value = theme.value === 'red' ? 'blue' : 'red'
  applyTheme(theme.value)
}

// 登录/退出时刷新状态（跨页面组件通信）
function refreshAuth() {
  isLogin.value = !!localStorage.getItem('h5_token')
  loadUser()
}
window.addEventListener('auth-changed', refreshAuth)
window.addEventListener('storage', refreshAuth)

function isActive(path: string) {
  return route.path === path || route.path.startsWith(path + '/')
}

async function fetchCategories() {
  try {
    const res: any = await getCategories()
    if (res.code === 0) {
      // 只取顶级（pid=0）
      topCategories.value = (res.data || []).filter((c: any) => c.pid === 0).slice(0, 6)
    }
  } catch (e) {}
}

function loadUser() {
  isLogin.value = !!localStorage.getItem('h5_token')
  try {
    const raw = localStorage.getItem('h5_user')
    if (raw) nickname.value = JSON.parse(raw).nickname || JSON.parse(raw).username || ''
  } catch (e) {}
}

async function handleLogout() {
  try {
    await logout()
  } catch (e) {}
  localStorage.removeItem('h5_token')
  localStorage.removeItem('h5_user')
  window.dispatchEvent(new Event('auth-changed'))
  router.push('/login')
}

onMounted(() => {
  applyTheme(theme.value)
  fetchCategories()
  loadUser()
})
</script>

<style scoped>
.h5-header {
  background: #fff;
  border-bottom: 1px solid var(--h5-border);
  position: sticky;
  top: 0;
  z-index: 100;
}

.header-inner {
  max-width: 1100px;
  margin: 0 auto;
  padding: 0 16px;
  height: 60px;
  display: flex;
  align-items: center;
  gap: 28px;
}

.header-logo {
  flex-shrink: 0;
}

.logo-img { display: block; height: 28px; width: auto; }
.logo-mark {
  font-size: 19px;
  font-weight: 800;
  color: var(--h5-primary);
  letter-spacing: -0.3px;
}

.header-nav {
  display: flex;
  gap: 4px;
  flex: 1;
  overflow-x: auto;
  -ms-overflow-style: none;
  scrollbar-width: none;
}

.header-nav::-webkit-scrollbar {
  display: none;
}

.nav-link {
  padding: 7px 14px;
  border-radius: var(--h5-radius);
  font-size: 14.5px;
  color: var(--h5-text-secondary);
  white-space: nowrap;
  transition: all 0.15s;
}

.nav-link:hover {
  background: var(--h5-bg);
  color: var(--h5-text);
}

.nav-link.active {
  background: var(--h5-primary-light);
  color: var(--h5-primary);
  font-weight: 600;
}

.header-right {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-shrink: 0;
}

.user-chip {
  font-size: 13.5px;
  color: var(--h5-text-secondary);
}

.btn-login {
  padding: 6px 18px;
  background: var(--h5-primary);
  color: #fff !important;
  border-radius: var(--h5-radius);
  font-size: 14px;
  transition: background 0.15s;
}

.btn-login:hover {
  background: var(--h5-primary-dark);
}

.btn-logout {
  padding: 6px 14px;
  background: transparent;
  border: 1px solid var(--h5-border);
  border-radius: var(--h5-radius);
  font-size: 13.5px;
  color: var(--h5-text-secondary);
  cursor: pointer;
}

.btn-logout:hover {
  border-color: var(--h5-danger);
  color: var(--h5-danger);
}

.theme-toggle {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 4px 10px;
  border: 1px solid var(--h5-border);
  border-radius: 14px;
  background: #fff;
  cursor: pointer;
  font-size: 12px;
  color: var(--h5-text-secondary);
  transition: all 0.2s;
}
.theme-toggle:hover {
  border-color: var(--h5-primary);
  color: var(--h5-primary);
}
.theme-dot {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  display: inline-block;
}
.dot-red { background: #db261e; }
.dot-blue { background: #1a73e8; }
</style>

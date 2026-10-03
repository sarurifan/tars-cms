<template>
  <header class="h5-header">
    <div class="header-inner">
      <!-- Logo -->
      <router-link to="/" class="header-logo">
        <span class="logo-mark">tars-cms</span>
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
const nickname = ref('')

const isLogin = computed(() => !!localStorage.getItem('h5_token'))

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
  router.push('/login')
}

onMounted(() => {
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
</style>

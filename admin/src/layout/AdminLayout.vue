<template>
  <div class="admin-layout">
    <!-- 顶部导航栏 -->
    <header class="layout-header">
      <div class="header-left">
        <img src="/logo.png" alt="tars-cms" class="admin-logo-img" />
        <span class="logo-text">tars-cms</span>
        <span class="logo-sub">管理后台</span>
      </div>
      <div class="header-right">
        <span class="user-name">{{ nickname }}</span>
        <el-button size="small" @click="handleLogout">退出</el-button>
      </div>
    </header>

    <div class="layout-body">
      <!-- 侧边栏 -->
      <aside class="layout-sidebar">
        <el-menu
          :default-active="activeMenu"
          :router="true"
          background-color="#1d2939"
          text-color="#a6b0bf"
          active-text-color="#ffffff"
          :unique-opened="true"
        >
          <el-menu-item index="/dashboard">
            <el-icon><Odometer /></el-icon>
            <span>仪表盘</span>
          </el-menu-item>

          <el-sub-menu index="article">
            <template #title>
              <el-icon><Document /></el-icon>
              <span>文章管理</span>
            </template>
            <el-menu-item index="/article/list">文章列表</el-menu-item>
            <el-menu-item index="/article/create">写文章</el-menu-item>
          </el-sub-menu>

          <el-sub-menu index="category">
            <template #title>
              <el-icon><Folder /></el-icon>
              <span>分类管理</span>
            </template>
            <el-menu-item index="/category/list">分类列表</el-menu-item>
          </el-sub-menu>

          <el-sub-menu index="member">
            <template #title>
              <el-icon><User /></el-icon>
              <span>成员管理</span>
            </template>
            <el-menu-item index="/member/list">成员列表</el-menu-item>
          </el-sub-menu>

          <el-sub-menu index="media">
            <template #title>
              <el-icon><Picture /></el-icon>
              <span>媒体管理</span>
            </template>
            <el-menu-item index="/media/list">媒体库</el-menu-item>
          </el-sub-menu>

          <el-sub-menu index="config">
            <template #title>
              <el-icon><Setting /></el-icon>
              <span>系统设置</span>
            </template>
            <el-menu-item index="/config/site">站点配置</el-menu-item>
          </el-sub-menu>
        </el-menu>
      </aside>

      <!-- 主内容区 -->
      <main class="layout-content">
        <router-view />
        <footer class="admin-footer">
          <span>© 2026 tars-cms · designed by sarurifan@gmail.com</span>
        </footer>
      </main>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getUser, clearToken } from '@/utils/auth'

const route = useRoute()
const router = useRouter()
const user = getUser()
const nickname = computed(() => user?.nickname || user?.username || 'admin')
const activeMenu = computed(() => route.path)

function handleLogout() {
  clearToken()
  router.push('/login')
}
</script>

<style scoped>
.admin-layout {
  height: 100vh;
  display: flex;
  flex-direction: column;
}

.layout-header {
  height: 56px;
  background: #1d2939;
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px;
  flex-shrink: 0;
}

.header-left {
  display: flex;
  align-items: baseline;
  gap: 8px;
}

.logo-text {
  font-size: 20px;
  font-weight: 700;
  letter-spacing: 0.5px;
  color: #ffffff;
}

.logo-sub {
  font-size: 13px;
  color: #a6b0bf;
}

.header-right {
  display: flex;
  align-items: center;
  gap: 12px;
}

.user-name {
  color: #a6b0bf;
  font-size: 13px;
}

.layout-body {
  flex: 1;
  display: flex;
  overflow: hidden;
}

.layout-sidebar {
  width: 210px;
  background: #1d2939;
  overflow-y: auto;
  flex-shrink: 0;
}

.layout-sidebar .el-menu {
  border-right: none;
}

.layout-content {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  background: #f0f2f5;
}

.admin-logo-img {
  height: 28px;
  width: auto;
  margin-right: 8px;
}

.admin-footer {
  text-align: center;
  padding: 24px 0 8px;
  color: #909399;
  font-size: 12px;
}

</style>

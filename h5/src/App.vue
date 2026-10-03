<template>
  <div class="h5-app">
    <!-- 顶部导航（h5 专属，独立实现，不复用 admin） -->
    <H5Header />

    <!-- 主内容 -->
    <main class="h5-main">
      <router-view />
    </main>

    <!-- 底部（h5 专属） -->
    <H5Footer />
  </div>
</template>

<script setup lang="ts">
import H5Header from '@/components/H5Header.vue'
import H5Footer from '@/components/H5Footer.vue'
</script>

<style scoped>
.h5-app {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

.h5-main {
  flex: 1;
  width: 100%;
  max-width: 1100px;
  margin: 0 auto;
  padding: 24px 16px 48px;
}
</style>

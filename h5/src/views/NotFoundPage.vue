<template>
  <div class="notfound-page">
    <div class="nf-card">
      <div class="nf-code">404</div>
      <h1 class="nf-title">页面不存在</h1>
      <p class="nf-desc">你访问的页面可能已被移动或删除。</p>
      <router-link to="/" class="nf-btn">返回首页</router-link>
    </div>
  </div>
</template>

<script setup lang="ts">
</script>

<style scoped>
.notfound-page {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 50vh;
}

.nf-card {
  text-align: center;
  background: #fff;
  border-radius: var(--h5-radius-lg);
  padding: 56px 48px;
  box-shadow: var(--h5-shadow-lg);
}

.nf-code {
  font-size: 88px;
  font-weight: 900;
  color: var(--h5-primary);
  line-height: 1;
  margin-bottom: 12px;
}

.nf-title {
  font-size: 22px;
  font-weight: 700;
  color: var(--h5-text);
  margin-bottom: 8px;
}

.nf-desc {
  font-size: 14.5px;
  color: var(--h5-text-secondary);
  margin-bottom: 26px;
}

.nf-btn {
  display: inline-block;
  padding: 11px 32px;
  background: var(--h5-primary);
  color: #fff !important;
  border-radius: var(--h5-radius);
  font-size: 15px;
  transition: background 0.15s;
}

.nf-btn:hover {
  background: var(--h5-primary-dark);
}
</style>

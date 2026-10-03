<template>
  <footer class="h5-footer">
    <div class="footer-inner">
      <div class="footer-top">
        <div class="footer-brand">
          <span class="brand-name">tars-cms</span>
          <p class="brand-desc">一个写给新手的大厂微服务实战项目，用 TARS 从零搭一个能跑的内容管理系统。</p>
        </div>
        <div class="footer-links">
          <div class="link-group">
            <h4 class="group-title">快速开始</h4>
            <router-link to="/" class="group-link">首页</router-link>
          </div>
          <div class="link-group">
            <h4 class="group-title">账号</h4>
            <router-link to="/login" class="group-link">登录</router-link>
            <router-link to="/register" class="group-link">注册</router-link>
          </div>
        </div>
      </div>
      <div class="footer-bottom">
        <span class="copyright">© {{ year }} tars-cms · GPL-3.0</span>
        <span class="powered">Powered by Tencent TARS</span>
      </div>
    </div>
  </footer>
</template>

<script setup lang="ts">
const year = new Date().getFullYear()
</script>

<style scoped>
.h5-footer {
  background: #1a1d21;
  color: #a6acb4;
  margin-top: 48px;
}

.footer-inner {
  max-width: 1100px;
  margin: 0 auto;
  padding: 40px 16px 24px;
}

.footer-top {
  display: flex;
  justify-content: space-between;
  gap: 40px;
  flex-wrap: wrap;
  padding-bottom: 24px;
  border-bottom: 1px solid #2c3036;
}

.footer-brand {
  max-width: 380px;
}

.brand-name {
  font-size: 20px;
  font-weight: 800;
  color: #fff;
}

.brand-desc {
  margin-top: 10px;
  font-size: 13.5px;
  line-height: 1.7;
  color: #8f959e;
}

.footer-links {
  display: flex;
  gap: 56px;
}

.link-group {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.group-title {
  font-size: 13.5px;
  font-weight: 600;
  color: #fff;
  margin-bottom: 4px;
}

.group-link {
  font-size: 13.5px;
  color: #8f959e;
}

.group-link:hover {
  color: #fff;
}

.footer-bottom {
  padding-top: 20px;
  display: flex;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 8px;
  font-size: 13px;
  color: #6b7280;
}
</style>

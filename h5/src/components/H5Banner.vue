<template>
  <!-- 轮播图（h5 专属组件，独立实现，不复用 admin） -->
  <section class="h5-banner" v-if="banners.length > 0">
    <div class="banner-track" :style="{ transform: `translateX(-${current * 100}%)` }">
      <div class="banner-slide" v-for="(b, i) in banners" :key="b.id">
        <router-link :to="`/article/${b.id}`" class="slide-link">
          <div class="slide-cover" v-if="b.cover" :style="{ backgroundImage: `url(${b.cover})` }"></div>
          <div class="slide-placeholder" v-else>
            <span class="placeholder-icon">📄</span>
          </div>
          <div class="slide-info">
            <span class="slide-tag" v-if="b.category">{{ b.category.name }}</span>
            <h3 class="slide-title">{{ b.title }}</h3>
            <p class="slide-summary">{{ b.summary }}</p>
          </div>
        </router-link>
      </div>
    </div>

    <!-- 指示点 -->
    <div class="banner-dots" v-if="banners.length > 1">
      <button
        class="dot"
        :class="{ active: current === i }"
        v-for="(b, i) in banners"
        :key="b.id"
        @click="goTo(i)"
        :aria-label="`第 ${i + 1} 张`"
      ></button>
    </div>

    <!-- 左右箭头 -->
    <button class="banner-arrow arrow-left" v-if="banners.length > 1" @click="prev">‹</button>
    <button class="banner-arrow arrow-right" v-if="banners.length > 1" @click="next">›</button>
  </section>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'

const props = defineProps<{
  banners: any[]
}>()

const current = ref(0)
let timer: any = null

function goTo(i: number) {
  current.value = i
  restart()
}

function next() {
  current.value = (current.value + 1) % props.banners.length
}

function prev() {
  current.value = (current.value - 1 + props.banners.length) % props.banners.length
}

function restart() {
  if (timer) clearInterval(timer)
  timer = setInterval(next, 5000)
}

onMounted(() => {
  if (props.banners.length > 1) restart()
})

onUnmounted(() => {
  if (timer) clearInterval(timer)
})
</script>

<style scoped>
.h5-banner {
  position: relative;
  border-radius: var(--h5-radius-lg);
  overflow: hidden;
  background: var(--h5-bg-card);
  box-shadow: var(--h5-shadow-md);
}

.banner-track {
  display: flex;
  transition: transform 0.5s cubic-bezier(0.4, 0, 0.2, 1);
}

.banner-slide {
  min-width: 100%;
}

.slide-link {
  display: block;
  color: inherit;
}

.slide-cover {
  height: 320px;
  background-size: cover;
  background-position: center;
  background-color: #1a1d21;
}

.slide-placeholder {
  height: 320px;
  background: linear-gradient(135deg, var(--h5-primary) 0%, #764ba2 100%);
  display: flex;
  align-items: center;
  justify-content: center;
}

.placeholder-icon {
  font-size: 64px;
  opacity: 0.5;
}

.slide-info {
  padding: 20px 24px;
}

.slide-tag {
  display: inline-block;
  font-size: 12px;
  color: var(--h5-primary);
  background: var(--h5-primary-light);
  padding: 2px 9px;
  border-radius: 3px;
  margin-bottom: 8px;
}

.slide-title {
  font-size: 22px;
  font-weight: 700;
  color: var(--h5-text);
  margin-bottom: 7px;
}

.slide-summary {
  font-size: 14.5px;
  color: var(--h5-text-secondary);
  line-height: 1.6;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.banner-dots {
  position: absolute;
  bottom: 14px;
  right: 20px;
  display: flex;
  gap: 7px;
}

.dot {
  width: 9px;
  height: 9px;
  border-radius: 50%;
  border: none;
  background: rgba(255, 255, 255, 0.5);
  cursor: pointer;
  transition: all 0.2s;
}

.dot.active {
  background: var(--h5-primary);
  transform: scale(1.25);
}

.banner-arrow {
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
  width: 40px;
  height: 40px;
  border-radius: 50%;
  border: none;
  background: rgba(255, 255, 255, 0.9);
  color: var(--h5-text);
  font-size: 22px;
  cursor: pointer;
  opacity: 0;
  transition: opacity 0.2s;
  box-shadow: var(--h5-shadow-md);
}

.h5-banner:hover .banner-arrow {
  opacity: 1;
}

.arrow-left {
  left: 14px;
}

.arrow-right {
  right: 14px;
}
</style>

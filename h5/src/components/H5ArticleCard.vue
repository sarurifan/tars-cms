<template>
  <!-- 文章卡片（h5 专属，独立实现，不复用 admin 表格） -->
  <article class="h5-card" @click="$router.push(`/article/${data.id}`)">
    <div class="card-cover" v-if="data.cover" :style="{ backgroundImage: `url(${data.cover})` }"></div>
    <div class="card-cover card-cover-placeholder" v-else>
      <span class="cover-letter">{{ (data.title || '?').charAt(0) }}</span>
    </div>

    <div class="card-body">
      <div class="card-meta">
        <span class="meta-tag" v-if="data.category">{{ data.category.name }}</span>
        <span class="meta-type" v-if="data.type">{{ typeLabel }}</span>
        <span class="meta-time">{{ publishTime }}</span>
      </div>

      <h3 class="card-title">
        <span class="title-badge top" v-if="data.is_top">置顶</span>
        <span class="title-badge focus" v-if="data.is_focus">焦点</span>
        {{ data.title }}
      </h3>

      <p class="card-summary">{{ data.summary }}</p>

      <div class="card-footer">
        <span class="footer-author" v-if="data.author">✍️ {{ data.author }}</span>
        <span class="footer-views">👁 {{ data.view_count || 0 }}</span>
      </div>
    </div>
  </article>
</template>

<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  data: any
}>()

const typeLabel = computed(() => {
  const map: Record<string, string> = {
    doc: '文档',
    article: '文章',
    news: '新闻',
    notice: '公告'
  }
  return map[props.data.type] || props.data.type
})

const publishTime = computed(() => {
  const t = props.data.publish_at || props.data.created_at
  if (!t) return ''
  const d = new Date(t)
  if (isNaN(d.getTime())) return String(t).slice(0, 10)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
})
</script>

<style scoped>
.h5-card {
  background: var(--h5-bg-card);
  border-radius: var(--h5-radius);
  overflow: hidden;
  box-shadow: var(--h5-shadow);
  cursor: pointer;
  transition: all 0.2s;
  display: flex;
  flex-direction: column;
}

.h5-card:hover {
  box-shadow: var(--h5-shadow-md);
  transform: translateY(-2px);
}

.card-cover {
  height: 160px;
  background-size: cover;
  background-position: center;
  background-color: #e8eaed;
}

.card-cover-placeholder {
  background: linear-gradient(135deg, var(--h5-primary-light) 0%, #f0f4ff 100%);
  display: flex;
  align-items: center;
  justify-content: center;
}

.cover-letter {
  font-size: 48px;
  font-weight: 800;
  color: var(--h5-primary);
  opacity: 0.4;
}

.card-body {
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 9px;
  flex: 1;
}

.card-meta {
  display: flex;
  align-items: center;
  gap: 7px;
  font-size: 12.5px;
  flex-wrap: wrap;
}

.meta-tag {
  color: var(--h5-primary);
  background: var(--h5-primary-light);
  padding: 1.5px 8px;
  border-radius: 3px;
}

.meta-type {
  color: var(--h5-text-tertiary);
}

.meta-time {
  color: var(--h5-text-tertiary);
  margin-left: auto;
}

.card-title {
  font-size: 16.5px;
  font-weight: 650;
  line-height: 1.45;
  color: var(--h5-text);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.title-badge {
  display: inline-block;
  font-size: 11px;
  padding: 1px 6px;
  border-radius: 3px;
  margin-right: 5px;
  vertical-align: middle;
  font-weight: 500;
}

.title-badge.top {
  background: #fff3e0;
  color: #e65100;
}

.title-badge.focus {
  background: #e3f2fd;
  color: #1565c0;
}

.card-summary {
  font-size: 14px;
  color: var(--h5-text-secondary);
  line-height: 1.65;
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
  flex: 1;
}

.card-footer {
  display: flex;
  justify-content: space-between;
  font-size: 13px;
  color: var(--h5-text-tertiary);
  padding-top: 9px;
  border-top: 1px solid var(--h5-bg);
}
</style>

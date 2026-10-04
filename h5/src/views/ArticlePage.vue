<template>
  <div class="article-page">
    <H5Loading :loading="loading" text="加载文章…" />

    <template v-if="!loading && article">
      <!-- 面包屑 -->
      <nav class="breadcrumb">
        <router-link to="/" class="crumb-link">首页</router-link>
        <span class="crumb-sep">›</span>
        <router-link
          v-if="article.category"
          :to="`/category/${article.category.slug || article.category.id}`"
          class="crumb-link"
        >
          {{ article.category.name }}
        </router-link>
        <span class="crumb-sep" v-if="article.category">›</span>
        <span class="crumb-current">{{ article.title }}</span>
      </nav>

      <!-- 文章头部 -->
      <header class="article-header">
        <div class="article-badges">
          <span class="badge badge-top" v-if="article.is_top">📌 置顶</span>
          <span class="badge badge-focus" v-if="article.is_focus">🎯 焦点</span>
          <span class="badge badge-banner" v-if="article.is_banner">🖼 轮播</span>
          <span class="badge badge-type" v-if="article.type">{{ typeLabel }}</span>
        </div>

        <h1 class="article-title">{{ article.title }}</h1>

        <p class="article-summary" v-if="article.summary">{{ article.summary }}</p>

        <div class="article-meta">
          <span class="meta-item" v-if="article.author && article.author.name">✍️ {{ article.author.name }}</span>
          <span class="meta-item" v-else-if="typeof article.author === 'string' && article.author">✍️ {{ article.author }}</span>
          <span class="meta-item" v-if="article.source">📎 来源：{{ article.source }}</span>
          <span class="meta-item">🕐 {{ publishText }}</span>
          <span class="meta-item">👁 {{ article.view_count || 0 }} 次阅读</span>
        </div>
      </header>

      <!-- 正文（v-html + 服务端 bluemonday 双保险） -->
      <article class="article-body">
        <div class="rich-content" v-html="sanitizedContent"></div>
      </article>

      <!-- 底部导航 -->
      <footer class="article-footer">
        <router-link to="/" class="footer-btn">← 返回首页</router-link>
        <router-link
          v-if="article.category"
          :to="`/category/${article.category.slug || article.category.id}`"
          class="footer-btn footer-btn-outline"
        >
          查看更多 {{ article.category.name }} →
        </router-link>
      </footer>
    </template>

    <H5Empty v-if="!loading && !article" text="文章不存在或已删除" icon="🔍">
      <router-link to="/" class="empty-link">返回首页</router-link>
    </H5Empty>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { getArticleDetail } from '@/api/content'
import H5Loading from '@/components/H5Loading.vue'
import H5Empty from '@/components/H5Empty.vue'

const route = useRoute()
const loading = ref(true)
const article = ref<any>(null)

const typeLabel = computed(() => {
  const map: Record<string, string> = {
    doc: '文档',
    article: '文章',
    news: '新闻',
    notice: '公告'
  }
  return article.value ? map[article.value.type] || article.value.type : ''
})

const publishText = computed(() => {
  if (!article.value) return ''
  const t = article.value.publish_at || article.value.created_at
  if (!t) return ''
  const d = new Date(t)
  if (isNaN(d.getTime())) return String(t)
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`
})

// 轻量 XSS 过滤（服务端 bluemonday 已净化，这里双保险）
const sanitizedContent = computed(() => {
  if (!article.value?.content) return ''
  let html = article.value.content
  // 移除 script/style 标签及其内容
  html = html.replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, '')
  // 移除事件处理器 on*
  html = html.replace(/\son\w+\s*=\s*"[^"]*"/gi, '')
  html = html.replace(/\son\w+\s*=\s*'[^']*'/gi, '')
  html = html.replace(/\son\w+\s*=\s*[^\s>]+/gi, '')
  // javascript: 协议
  html = html.replace(/(href|src)\s*=\s*["']?\s*javascript:[^"'>\s]*/gi, '$1="#"')
  return html
})

async function fetchArticle() {
  loading.value = true
  try {
    const id = Number(route.params.id)
    const res: any = await getArticleDetail(id)
    if (res.code === 0) {
      article.value = res.data
      document.title = res.data.title + ' - tars-cms'
    }
  } catch (e) {
  } finally {
    loading.value = false
  }
}

onMounted(fetchArticle)
</script>

<style scoped>
.article-page {
  max-width: 820px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 20px;
}

/* 面包屑 */
.breadcrumb {
  display: flex;
  align-items: center;
  gap: 7px;
  font-size: 13.5px;
  flex-wrap: wrap;
}

.crumb-link {
  color: var(--h5-text-secondary);
}

.crumb-link:hover {
  color: var(--h5-primary);
}

.crumb-sep {
  color: var(--h5-text-tertiary);
}

.crumb-current {
  color: var(--h5-text-tertiary);
  max-width: 300px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* 文章头 */
.article-header {
  background: #fff;
  border-radius: var(--h5-radius-lg);
  padding: 32px 32px 24px;
  box-shadow: var(--h5-shadow);
}

.article-badges {
  display: flex;
  gap: 7px;
  flex-wrap: wrap;
  margin-bottom: 14px;
}

.badge {
  font-size: 12px;
  padding: 3px 10px;
  border-radius: 4px;
  font-weight: 500;
}

.badge-top {
  background: #fff3e0;
  color: #e65100;
}

.badge-focus {
  background: #e3f2fd;
  color: #1565c0;
}

.badge-banner {
  background: #e8f5e9;
  color: #2e7d32;
}

.badge-type {
  background: var(--h5-bg);
  color: var(--h5-text-secondary);
}

.article-title {
  font-size: 32px;
  font-weight: 800;
  line-height: 1.35;
  color: var(--h5-text);
  margin-bottom: 12px;
}

.article-summary {
  font-size: 16px;
  color: var(--h5-text-secondary);
  line-height: 1.7;
  padding: 12px 16px;
  background: var(--h5-bg);
  border-radius: var(--h5-radius);
  margin-bottom: 16px;
}

.article-meta {
  display: flex;
  gap: 18px;
  flex-wrap: wrap;
  font-size: 13.5px;
  color: var(--h5-text-tertiary);
}

/* 正文 */
.article-body {
  background: #fff;
  border-radius: var(--h5-radius-lg);
  padding: 32px;
  box-shadow: var(--h5-shadow);
}

/* 底部 */
.article-footer {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}

.footer-btn {
  padding: 11px 24px;
  background: var(--h5-primary);
  color: #fff !important;
  border-radius: var(--h5-radius);
  font-size: 14.5px;
  transition: all 0.15s;
}

.footer-btn:hover {
  background: var(--h5-primary-dark);
}

.footer-btn-outline {
  background: #fff;
  color: var(--h5-primary) !important;
  border: 1px solid var(--h5-primary);
}

.footer-btn-outline:hover {
  background: var(--h5-primary-light);
}

.empty-link {
  margin-top: 8px;
}
</style>

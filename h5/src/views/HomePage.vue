<template>
  <div class="home-page">
    <!-- 轮播图 -->
    <H5Banner :banners="home.banners || []" />

    <!-- 置顶文章 -->
    <section class="section" v-if="home.topArticles && home.topArticles.length">
      <div class="section-head">
        <h2 class="section-title">📌 置顶推荐</h2>
      </div>
      <div class="article-grid">
        <H5ArticleCard v-for="a in home.topArticles" :key="a.id" :data="a" />
      </div>
    </section>

    <!-- 焦点文章 -->
    <section class="section" v-if="home.focusArticles && home.focusArticles.length">
      <div class="section-head">
        <h2 class="section-title">🎯 焦点关注</h2>
      </div>
      <div class="article-grid">
        <H5ArticleCard v-for="a in home.focusArticles" :key="a.id" :data="a" />
      </div>
    </section>

    <!-- 最新文章 -->
    <section class="section">
      <div class="section-head">
        <h2 class="section-title">🕐 最新文章</h2>
        <div class="section-more" v-if="home.categories && home.categories.length">
          <router-link
            v-for="c in home.categories.slice(0, 5)"
            :key="c.id"
            :to="`/category/${c.slug || c.id}`"
            class="more-chip"
          >
            {{ c.name }}
          </router-link>
        </div>
      </div>

      <H5Loading :loading="loading" />
      <H5Empty v-if="!loading && (!home.latest || home.latest.length === 0)" text="暂无文章" />

      <div class="article-grid" v-if="home.latest && home.latest.length">
        <H5ArticleCard v-for="a in home.latest" :key="a.id" :data="a" />
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { getHome } from '@/api/content'
import H5Banner from '@/components/H5Banner.vue'
import H5ArticleCard from '@/components/H5ArticleCard.vue'
import H5Loading from '@/components/H5Loading.vue'
import H5Empty from '@/components/H5Empty.vue'

const loading = ref(true)
const home = reactive<any>({
  banners: [],
  topArticles: [],
  focusArticles: [],
  latest: [],
  categories: [],
  config: {}
})

async function fetchHome() {
  loading.value = true
  try {
    const res: any = await getHome()
    if (res.code === 0) {
      Object.assign(home, res.data)
    }
  } catch (e) {
  } finally {
    loading.value = false
  }
}

onMounted(fetchHome)
</script>

<style scoped>
.home-page {
  display: flex;
  flex-direction: column;
  gap: 32px;
}

.section {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.section-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 12px;
}

.section-title {
  font-size: 19px;
  font-weight: 700;
  color: var(--h5-text);
}

.section-more {
  display: flex;
  gap: 7px;
  flex-wrap: wrap;
}

.more-chip {
  font-size: 13px;
  color: var(--h5-text-secondary);
  padding: 4px 12px;
  background: #fff;
  border: 1px solid var(--h5-border);
  border-radius: 20px;
  transition: all 0.15s;
}

.more-chip:hover {
  border-color: var(--h5-primary);
  color: var(--h5-primary);
}

.article-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 18px;
}
</style>

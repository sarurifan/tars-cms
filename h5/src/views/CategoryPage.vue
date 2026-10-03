<template>
  <div class="category-page">
    <!-- 页面头 -->
    <div class="page-head">
      <h1 class="page-title">{{ currentCategory ? currentCategory.name : '全部文章' }}</h1>
      <p class="page-desc" v-if="currentCategory && currentCategory.slug">
        分类标识：{{ currentCategory.slug }}
      </p>
    </div>

    <!-- 分类筛选 -->
    <div class="category-filter">
      <router-link to="/category/" class="filter-chip" :class="{ active: !currentSlug }">全部</router-link>
      <router-link
        v-for="c in categories"
        :key="c.id"
        :to="`/category/${c.slug || c.id}`"
        class="filter-chip"
        :class="{ active: String(c.slug || c.id) === currentSlug }"
      >
        {{ c.name }}
      </router-link>
    </div>

    <!-- 加载 / 空 / 列表 -->
    <H5Loading :loading="loading" />

    <H5Empty v-if="!loading && list.length === 0" text="该分类暂无文章">
      <router-link to="/" class="empty-link">返回首页</router-link>
    </H5Empty>

    <div class="article-list" v-if="list.length">
      <H5ArticleCard v-for="a in list" :key="a.id" :data="a" />
    </div>

    <!-- 分页 -->
    <H5Pagination :page="page" :size="size" :total="total" @change="handlePageChange" />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { getArticles, getCategories } from '@/api/content'
import H5ArticleCard from '@/components/H5ArticleCard.vue'
import H5Pagination from '@/components/H5Pagination.vue'
import H5Loading from '@/components/H5Loading.vue'
import H5Empty from '@/components/H5Empty.vue'

const route = useRoute()
const loading = ref(true)
const list = ref<any[]>([])
const categories = ref<any[]>([])
const total = ref(0)
const page = ref(1)
const size = ref(12)

const currentSlug = computed(() => String(route.params.slug || ''))

const currentCategory = computed(() => {
  if (!currentSlug.value) return null
  return categories.value.find(
    (c) => String(c.slug || c.id) === currentSlug.value
  ) || null
})

async function fetchCategories() {
  try {
    const res: any = await getCategories()
    if (res.code === 0) categories.value = res.data || []
  } catch (e) {}
}

async function fetchList() {
  loading.value = true
  try {
    const cat = currentCategory.value
    const res: any = await getArticles({
      categoryId: cat ? cat.id : undefined,
      page: page.value,
      size: size.value
    })
    if (res.code === 0) {
      list.value = res.data.list || []
      total.value = res.data.total || 0
    }
  } catch (e) {
  } finally {
    loading.value = false
  }
}

function handlePageChange(p: number) {
  page.value = p
  fetchList()
  window.scrollTo({ top: 0, behavior: 'smooth' })
}

// 路由变化时重置并加载
watch(
  () => route.params.slug,
  () => {
    page.value = 1
    fetchList()
  }
)

onMounted(() => {
  fetchCategories().then(() => fetchList())
})
</script>

<style scoped>
.category-page {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.page-head {
  background: #fff;
  border-radius: var(--h5-radius-lg);
  padding: 28px 24px;
  box-shadow: var(--h5-shadow);
}

.page-title {
  font-size: 26px;
  font-weight: 750;
  color: var(--h5-text);
}

.page-desc {
  font-size: 14px;
  color: var(--h5-text-tertiary);
  margin-top: 6px;
}

.category-filter {
  display: flex;
  gap: 9px;
  flex-wrap: wrap;
}

.filter-chip {
  padding: 7px 18px;
  background: #fff;
  border: 1px solid var(--h5-border);
  border-radius: 22px;
  font-size: 14px;
  color: var(--h5-text-secondary);
  transition: all 0.15s;
}

.filter-chip:hover {
  border-color: var(--h5-primary);
  color: var(--h5-primary);
}

.filter-chip.active {
  background: var(--h5-primary);
  border-color: var(--h5-primary);
  color: #fff;
  font-weight: 500;
}

.article-list {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 18px;
}

.empty-link {
  margin-top: 6px;
  font-size: 14px;
}
</style>

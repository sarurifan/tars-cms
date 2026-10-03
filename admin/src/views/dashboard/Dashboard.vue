<template>
  <div class="dashboard-page">
    <div class="stat-cards">
      <div class="stat-card" v-for="card in statCards" :key="card.label">
        <div class="stat-value">{{ card.value }}</div>
        <div class="stat-label">{{ card.label }}</div>
      </div>
    </div>

    <div class="dash-grid">
      <div class="dash-panel">
        <h3 class="panel-title">快捷入口</h3>
        <div class="quick-actions">
          <el-button type="primary" @click="$router.push('/article/create')">写文章</el-button>
          <el-button @click="$router.push('/article/list')">文章列表</el-button>
          <el-button @click="$router.push('/category/list')">分类管理</el-button>
          <el-button @click="$router.push('/member/list')">成员管理</el-button>
        </div>
      </div>

      <div class="dash-panel">
        <h3 class="panel-title">最新文章</h3>
        <div v-if="latest.length" class="latest-list">
          <div class="latest-item" v-for="a in latest" :key="a.id">
            <span class="latest-title">{{ a.title }}</span>
            <span class="latest-time">{{ a.publish_at }}</span>
          </div>
        </div>
        <div v-else class="empty-tip">暂无文章</div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { getHome } from '@/api/cms'

const statCards = ref([
  { label: '轮播图', value: 0 },
  { label: '置顶文章', value: 0 },
  { label: '焦点文章', value: 0 },
  { label: '最新文章', value: 0 }
])

const latest = ref<any[]>([])

onMounted(async () => {
  try {
    const res: any = await getHome()
    if (res.code === 0) {
      const d = res.data
      statCards.value[0].value = (d.banners || []).length
      statCards.value[1].value = (d.topArticles || []).length
      statCards.value[2].value = (d.focusArticles || []).length
      statCards.value[3].value = (d.latest || []).length
      latest.value = (d.latest || []).slice(0, 8)
    }
  } catch (e) {}
})
</script>

<style scoped>
.dashboard-page {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.stat-cards {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 16px;
}

.stat-card {
  background: #fff;
  border-radius: 6px;
  padding: 20px;
  text-align: center;
}

.stat-value {
  font-size: 32px;
  font-weight: 700;
  color: #409eff;
  line-height: 1.2;
}

.stat-label {
  font-size: 13px;
  color: #909399;
  margin-top: 6px;
}

.dash-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}

.dash-panel {
  background: #fff;
  border-radius: 6px;
  padding: 20px;
}

.panel-title {
  font-size: 15px;
  font-weight: 600;
  color: #303133;
  margin-bottom: 16px;
}

.quick-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}

.latest-list {
  display: flex;
  flex-direction: column;
}

.latest-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 9px 0;
  border-bottom: 1px solid #f0f0f0;
}

.latest-title {
  font-size: 13px;
  color: #303133;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.latest-time {
  font-size: 12px;
  color: #c0c4cc;
  flex-shrink: 0;
  margin-left: 12px;
}

.empty-tip {
  color: #c0c4cc;
  font-size: 13px;
  text-align: center;
  padding: 30px 0;
}
</style>

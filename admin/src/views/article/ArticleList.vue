<template>
  <div class="article-list-page page-container">
    <div class="table-toolbar">
      <div class="toolbar-left">
        <el-select
          v-model="filter.categoryId"
          placeholder="全部分类"
          clearable
          style="width: 180px"
          @change="handleSearch"
        >
          <el-option
            v-for="c in categories"
            :key="c.id"
            :label="c.name"
            :value="c.id"
          />
        </el-select>
        <el-select v-model="filter.status" placeholder="全部状态" clearable style="width: 140px; margin-left: 10px" @change="handleSearch">
          <el-option label="草稿" :value="0" />
          <el-option label="已发布" :value="1" />
          <el-option label="已归档" :value="2" />
        </el-select>
        <el-input
          v-model="filter.keyword"
          placeholder="标题搜索"
          clearable
          style="width: 200px; margin-left: 10px"
          @keyup.enter="handleSearch"
          @clear="handleSearch"
        />
      </div>
      <div class="toolbar-right">
        <el-button type="primary" @click="$router.push('/article/create')">写文章</el-button>
      </div>
    </div>

    <el-table :data="list" v-loading="loading" stripe>
      <el-table-column prop="id" label="ID" width="60" />
      <el-table-column prop="title" label="标题" min-width="200" show-overflow-tooltip>
        <template #default="{ row }">
          <span class="article-title" @click="handleEdit(row)">{{ row.title }}</span>
        </template>
      </el-table-column>
      <el-table-column label="分类" width="130">
        <template #default="{ row }">
          <el-tag v-if="row.category" size="small" type="info">{{ row.category.name }}</el-tag>
          <span v-else>-</span>
        </template>
      </el-table-column>
      <el-table-column prop="type" label="类型" width="90">
        <template #default="{ row }">
          <span>{{ typeMap[row.type] || row.type }}</span>
        </template>
      </el-table-column>
      <el-table-column prop="view_count" label="浏览" width="80" />
      <el-table-column prop="status" label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.status === 1 ? 'success' : row.status === 0 ? 'info' : 'warning'" size="small">
            {{ statusMap[row.status] || '未知' }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="sort" label="排序" width="70" />
      <el-table-column prop="publish_at" label="发布时间" width="170" />
      <el-table-column label="操作" width="220" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="handleEdit(row)">编辑</el-button>
          <el-button size="small" type="danger" @click="handleDelete(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <div class="pagination-wrap">
      <el-pagination
        v-model:current-page="page"
        v-model:page-size="size"
        :total="total"
        :page-sizes="[10, 20, 50]"
        layout="total, sizes, prev, pager, next, jumper"
        @current-change="fetchList"
        @size-change="handleSizeChange"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { getAdminArticles, deleteArticle } from '@/api/admin'
import { getAdminCategories } from '@/api/admin'

const router = useRouter()
const loading = ref(false)
const list = ref<any[]>([])
const categories = ref<any[]>([])
const total = ref(0)
const page = ref(1)
const size = ref(10)

const filter = reactive({
  categoryId: undefined as number | undefined,
  status: undefined as number | undefined,
  keyword: ''
})

const typeMap: Record<string, string> = {
  doc: '文档',
  article: '文章',
  news: '新闻',
  notice: '公告'
}

const statusMap: Record<number, string> = {
  0: '草稿',
  1: '已发布',
  2: '已归档'
}

async function fetchList() {
  loading.value = true
  try {
    const res: any = await getAdminArticles({
      categoryId: filter.categoryId,
      status: filter.status,
      page: page.value,
      size: size.value
    })
    if (res.code === 0) {
      list.value = res.data.list || []
      total.value = res.data.total || 0
    }
  } finally {
    loading.value = false
  }
}

async function fetchCategories() {
  try {
    const res: any = await getAdminCategories()
    if (res.code === 0) {
      categories.value = res.data || []
    }
  } catch (e) {}
}

function handleSearch() {
  page.value = 1
  fetchList()
}

function handleSizeChange() {
  page.value = 1
  fetchList()
}

function handleEdit(row: any) {
  router.push(`/article/edit/${row.id}`)
}

async function handleDelete(row: any) {
  await ElMessageBox.confirm(`确定删除文章「${row.title}」？`, '提示', {
    type: 'warning',
    confirmButtonText: '确定',
    cancelButtonText: '取消'
  })
  try {
    const res: any = await deleteArticle(row.id)
    if (res.code === 0) {
      ElMessage.success('删除成功')
      fetchList()
    }
  } catch (e) {}
}

onMounted(() => {
  fetchList()
  fetchCategories()
})
</script>

<style scoped>
.article-title {
  cursor: pointer;
  color: #303133;
}

.article-title:hover {
  color: #409eff;
}
</style>

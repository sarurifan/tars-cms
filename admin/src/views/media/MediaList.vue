<template>
  <div class="media-list-page page-container">
    <div class="table-toolbar">
      <div class="toolbar-left">
        <h3 class="page-heading">媒体库</h3>
      </div>
      <div class="toolbar-right">
        <el-upload
          :action="uploadUrl"
          :headers="uploadHeaders"
          :show-file-list="false"
          :on-success="handleUploadSuccess"
          :on-error="handleUploadError"
        >
          <el-button type="primary">上传图片</el-button>
        </el-upload>
      </div>
    </div>

    <el-table :data="list" v-loading="loading" stripe>
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column label="预览" width="100">
        <template #default="{ row }">
          <el-image
            :src="row.url"
            :preview-src-list="[row.url]"
            preview-teleported
            fit="cover"
            style="width: 60px; height: 40px; border-radius: 3px"
          />
        </template>
      </el-table-column>
      <el-table-column prop="name" label="文件名" min-width="180" show-overflow-tooltip />
      <el-table-column prop="mime_type" label="类型" width="120" />
      <el-table-column prop="size" label="大小" width="110">
        <template #default="{ row }">
          <span>{{ formatSize(row.size) }}</span>
        </template>
      </el-table-column>
      <el-table-column prop="driver" label="存储" width="80">
        <template #default="{ row }">
          <el-tag size="small" type="info">{{ row.driver || 'local' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="created_at" label="上传时间" width="170" />
    </el-table>

    <div class="pagination-wrap">
      <el-pagination
        v-model:current-page="page"
        v-model:page-size="size"
        :total="total"
        :page-sizes="[12, 24, 48]"
        layout="total, sizes, prev, pager, next"
        @current-change="fetchList"
        @size-change="handleSizeChange"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { getAdminMedia } from '@/api/admin'
import { getToken } from '@/utils/auth'

const loading = ref(false)
const list = ref<any[]>([])
const total = ref(0)
const page = ref(1)
const size = ref(12)

// 上传地址：经网关
const uploadUrl = '/api/admin/upload/image'
const uploadHeaders = computed(() => ({
  Authorization: 'Bearer ' + getToken()
}))

function formatSize(bytes: number) {
  if (!bytes) return '-'
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  return (bytes / 1024 / 1024).toFixed(2) + ' MB'
}

async function fetchList() {
  loading.value = true
  try {
    const res: any = await getAdminMedia({ page: page.value, size: size.value })
    if (res.code === 0) {
      list.value = res.data.list || []
      total.value = res.data.total || 0
    }
  } finally {
    loading.value = false
  }
}

function handleSizeChange() {
  page.value = 1
  fetchList()
}

function handleUploadSuccess(res: any) {
  if (res.code === 0) {
    ElMessage.success('上传成功')
    fetchList()
  } else {
    ElMessage.error(res.msg || '上传失败')
  }
}

function handleUploadError() {
  ElMessage.error('上传失败')
}

onMounted(fetchList)
</script>

<style scoped>
.page-heading {
  font-size: 15px;
  font-weight: 600;
  color: #303133;
  margin: 0;
}
</style>

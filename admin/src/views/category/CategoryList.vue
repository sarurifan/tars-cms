<template>
  <div class="category-list-page page-container">
    <div class="table-toolbar">
      <div class="toolbar-left">
        <el-input
          v-model="keyword"
          placeholder="分类名称搜索"
          clearable
          style="width: 220px"
          @keyup.enter="handleSearch"
          @clear="handleSearch"
        />
      </div>
      <div class="toolbar-right">
        <el-button type="primary" @click="openDialog()">新增分类</el-button>
      </div>
    </div>

    <el-table :data="list" v-loading="loading" row-key="id" stripe>
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column prop="name" label="名称" min-width="140" />
      <el-table-column prop="slug" label="Slug" min-width="140" />
      <el-table-column prop="pid" label="父级" width="90">
        <template #default="{ row }">
          <span>{{ row.pid === 0 ? '顶级分类' : getParentName(row.pid) }}</span>
        </template>
      </el-table-column>
      <el-table-column prop="sort" label="排序" width="80" />
      <el-table-column prop="article_count" label="文章数" width="90" />
      <el-table-column label="操作" width="200" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="openDialog(row)">编辑</el-button>
          <el-button size="small" type="danger" @click="handleDelete(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <!-- 新增/编辑对话框 -->
    <el-dialog v-model="dialogVisible" :title="isEdit ? '编辑分类' : '新增分类'" width="500px">
      <el-form :model="form" label-width="80px">
        <el-form-item label="名称" required>
          <el-input v-model="form.name" placeholder="分类名称" />
        </el-form-item>
        <el-form-item label="Slug">
          <el-input v-model="form.slug" placeholder="URL 标识（可选）" />
        </el-form-item>
        <el-form-item label="父级">
          <el-select v-model="form.pid" style="width: 100%">
            <el-option label="顶级分类" :value="0" />
            <el-option v-for="c in parentOptions" :key="c.id" :label="c.name" :value="c.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="排序">
          <el-input-number v-model="form.sort" :min="0" :max="9999" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="handleSave">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, computed, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { getAdminCategories, createCategory, updateCategory, deleteCategory } from '@/api/admin'

const loading = ref(false)
const saving = ref(false)
const list = ref<any[]>([])
const keyword = ref('')
const dialogVisible = ref(false)
const isEdit = ref(false)
const editId = ref(0)

const form = reactive({
  name: '',
  slug: '',
  pid: 0,
  sort: 0
})

const parentOptions = computed(() =>
  list.value.filter((c) => c.pid === 0 && c.id !== editId.value)
)

function getParentName(pid: number) {
  const p = list.value.find((c) => c.id === pid)
  return p ? p.name : '未知'
}

async function fetchList() {
  loading.value = true
  try {
    const res: any = await getAdminCategories()
    if (res.code === 0) {
      let rows = res.data || []
      if (keyword.value) {
        const k = keyword.value.toLowerCase()
        rows = rows.filter(
          (r: any) => r.name.toLowerCase().includes(k) || (r.slug || '').toLowerCase().includes(k)
        )
      }
      list.value = rows
    }
  } finally {
    loading.value = false
  }
}

function handleSearch() {
  fetchList()
}

function openDialog(row?: any) {
  isEdit.value = !!row
  editId.value = row?.id || 0
  form.name = row?.name || ''
  form.slug = row?.slug || ''
  form.pid = row?.pid || 0
  form.sort = row?.sort || 0
  dialogVisible.value = true
}

async function handleSave() {
  if (!form.name) {
    ElMessage.warning('请输入名称')
    return
  }
  saving.value = true
  try {
    const payload = { name: form.name, slug: form.slug, pid: form.pid, sort: form.sort }
    const res: any = isEdit.value
      ? await updateCategory(editId.value, payload)
      : await createCategory(payload)
    if (res.code === 0) {
      ElMessage.success(isEdit.value ? '更新成功' : '创建成功')
      dialogVisible.value = false
      fetchList()
    }
  } catch (e) {
  } finally {
    saving.value = false
  }
}

async function handleDelete(row: any) {
  await ElMessageBox.confirm(`确定删除分类「${row.name}」？`, '提示', { type: 'warning' })
  try {
    const res: any = await deleteCategory(row.id)
    if (res.code === 0) {
      ElMessage.success('删除成功')
      fetchList()
    }
  } catch (e) {}
}

onMounted(fetchList)
</script>

<template>
  <div class="member-list-page page-container">
    <div class="table-toolbar">
      <div class="toolbar-left">
        <h3 class="page-heading">成员管理</h3>
      </div>
      <div class="toolbar-right">
        <el-button type="primary" @click="openDialog()">新增成员</el-button>
      </div>
    </div>

    <el-table :data="list" v-loading="loading" stripe>
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column label="头像" width="80">
        <template #default="{ row }">
          <el-avatar :size="36" :src="row.avatar || ''">
            {{ (row.name || '?').charAt(0) }}
          </el-avatar>
        </template>
      </el-table-column>
      <el-table-column prop="name" label="姓名" min-width="120" />
      <el-table-column prop="title" label="职位" min-width="120" />
      <el-table-column prop="role" label="角色" width="110">
        <template #default="{ row }">
          <el-tag size="small" :type="roleTagType(row.role)">{{ row.role || 'member' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="bio" label="简介" min-width="200" show-overflow-tooltip />
      <el-table-column prop="sort" label="排序" width="70" />
      <el-table-column label="操作" width="200" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="openDialog(row)">编辑</el-button>
          <el-button size="small" type="danger" @click="handleDelete(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <!-- 新增/编辑对话框 -->
    <el-dialog v-model="dialogVisible" :title="isEdit ? '编辑成员' : '新增成员'" width="560px">
      <el-form :model="form" label-width="80px">
        <el-form-item label="姓名" required>
          <el-input v-model="form.name" placeholder="成员姓名" />
        </el-form-item>
        <el-form-item label="职位">
          <el-input v-model="form.title" placeholder="职位/头衔" />
        </el-form-item>
        <el-form-item label="角色">
          <el-select v-model="form.role" style="width: 100%">
            <el-option label="成员" value="member" />
            <el-option label="编辑" value="editor" />
            <el-option label="管理员" value="admin" />
          </el-select>
        </el-form-item>
        <el-form-item label="头像 URL">
          <el-input v-model="form.avatar" placeholder="头像图片地址（可选）" />
        </el-form-item>
        <el-form-item label="简介">
          <el-input v-model="form.bio" type="textarea" :rows="3" placeholder="个人简介（可选）" />
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
import { ref, reactive, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { getAdminMembers, createMember, updateMember, deleteMember } from '@/api/admin'

const loading = ref(false)
const saving = ref(false)
const list = ref<any[]>([])
const dialogVisible = ref(false)
const isEdit = ref(false)
const editId = ref(0)

const form = reactive({
  name: '',
  title: '',
  role: 'member',
  avatar: '',
  bio: '',
  sort: 0
})

function roleTagType(role: string) {
  if (role === 'admin') return 'danger'
  if (role === 'editor') return 'warning'
  return 'info'
}

async function fetchList() {
  loading.value = true
  try {
    const res: any = await getAdminMembers()
    if (res.code === 0) list.value = res.data || []
  } finally {
    loading.value = false
  }
}

function openDialog(row?: any) {
  isEdit.value = !!row
  editId.value = row?.id || 0
  form.name = row?.name || ''
  form.title = row?.title || ''
  form.role = row?.role || 'member'
  form.avatar = row?.avatar || ''
  form.bio = row?.bio || ''
  form.sort = row?.sort || 0
  dialogVisible.value = true
}

async function handleSave() {
  if (!form.name) {
    ElMessage.warning('请输入姓名')
    return
  }
  saving.value = true
  try {
    const payload = { ...form }
    const res: any = isEdit.value
      ? await updateMember(editId.value, payload)
      : await createMember(payload)
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
  await ElMessageBox.confirm(`确定删除成员「${row.name}」？`, '提示', { type: 'warning' })
  try {
    const res: any = await deleteMember(row.id)
    if (res.code === 0) {
      ElMessage.success('删除成功')
      fetchList()
    }
  } catch (e) {}
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

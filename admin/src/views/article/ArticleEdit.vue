<template>
  <div class="article-edit-page page-container">
    <div class="edit-header">
      <h2 class="edit-title">{{ isEdit ? '编辑文章' : '写文章' }}</h2>
      <div class="edit-actions">
        <el-button @click="$router.back()">取消</el-button>
        <el-button type="primary" :loading="saving" @click="handleSave(1)">发布</el-button>
        <el-button :loading="saving" @click="handleSave(0)">存草稿</el-button>
      </div>
    </div>

    <el-form :model="form" label-width="90px" class="edit-form">
      <el-form-item label="标题" required>
        <el-input v-model="form.title" placeholder="文章标题" maxlength="200" show-word-limit />
      </el-form-item>

      <el-form-item label="摘要">
        <el-input v-model="form.summary" type="textarea" :rows="2" placeholder="文章摘要（可选）" maxlength="500" show-word-limit />
      </el-form-item>

      <div class="form-row">
        <el-form-item label="分类" required>
          <el-select v-model="form.categoryId" placeholder="选择分类" style="width: 180px">
            <el-option v-for="c in categories" :key="c.id" :label="c.name" :value="c.id" />
          </el-select>
        </el-form-item>

        <el-form-item label="类型">
          <el-select v-model="form.type" style="width: 140px">
            <el-option label="文档" value="doc" />
            <el-option label="文章" value="article" />
            <el-option label="新闻" value="news" />
            <el-option label="公告" value="notice" />
          </el-select>
        </el-form-item>

        <el-form-item label="排序">
          <el-input-number v-model="form.sort" :min="0" :max="9999" style="width: 140px" />
        </el-form-item>
      </div>

      <el-form-item label="封面">
        <el-input v-model="form.cover" placeholder="封面图片 URL（可选）" style="max-width: 500px" />
      </el-form-item>

      <el-form-item label="来源">
        <el-input v-model="form.source" placeholder="文章来源（可选）" style="max-width: 300px" />
      </el-form-item>

      <el-form-item label="选项">
        <el-checkbox v-model="form.isTop">置顶</el-checkbox>
        <el-checkbox v-model="form.isFocus">焦点</el-checkbox>
        <el-checkbox v-model="form.isBanner">轮播图</el-checkbox>
      </el-form-item>

      <el-form-item label="正文" required>
        <div class="editor-wrap">
          <textarea
            v-model="form.content"
            class="content-editor"
            placeholder="支持 HTML 富文本。服务端会用 bluemonday 做 XSS 净化。"
          ></textarea>
        </div>
      </el-form-item>
    </el-form>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { getAdminCategories, createArticle, updateArticle } from '@/api/admin'
import { getArticleDetail } from '@/api/cms'

const route = useRoute()
const router = useRouter()
const saving = ref(false)
const categories = ref<any[]>([])

const isEdit = computed(() => !!route.params.id)

const form = reactive({
  title: '',
  summary: '',
  content: '',
  categoryId: undefined as number | undefined,
  type: 'article',
  cover: '',
  source: '',
  sort: 0,
  isTop: false,
  isFocus: false,
  isBanner: false
})

async function fetchCategories() {
  try {
    const res: any = await getAdminCategories()
    if (res.code === 0) categories.value = res.data || []
  } catch (e) {}
}

async function fetchDetail() {
  if (!route.params.id) return
  try {
    const res: any = await getArticleDetail(Number(route.params.id))
    if (res.code === 0) {
      const d = res.data
      form.title = d.title || ''
      form.summary = d.summary || ''
      form.content = d.content || ''
      form.categoryId = d.category?.id
      form.type = d.type || 'article'
      form.cover = d.cover || ''
      form.source = d.source || ''
      form.sort = d.sort || 0
      form.isTop = !!d.is_top
      form.isFocus = !!d.is_focus
      form.isBanner = !!d.is_banner
    }
  } catch (e) {}
}

async function handleSave(status: number) {
  if (!form.title) {
    ElMessage.warning('请输入标题')
    return
  }
  if (!form.categoryId) {
    ElMessage.warning('请选择分类')
    return
  }
  saving.value = true
  try {
    const payload: any = {
      title: form.title,
      summary: form.summary,
      content: form.content,
      categoryId: form.categoryId,
      type: form.type,
      cover: form.cover,
      source: form.source,
      sort: form.sort,
      isTop: form.isTop,
      isFocus: form.isFocus,
      isBanner: form.isBanner
    }
    let res: any
    if (isEdit.value) {
      res = await updateArticle(Number(route.params.id), payload)
    } else {
      res = await createArticle(payload)
    }
    if (res.code === 0) {
      ElMessage.success(isEdit.value ? '更新成功' : '创建成功')
      router.push('/article/list')
    }
  } catch (e) {
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  fetchCategories()
  fetchDetail()
})
</script>

<style scoped>
.edit-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
}

.edit-title {
  font-size: 18px;
  font-weight: 600;
}

.edit-actions {
  display: flex;
  gap: 10px;
}

.form-row {
  display: flex;
  gap: 24px;
  flex-wrap: wrap;
}

.editor-wrap {
  width: 100%;
}

.content-editor {
  width: 100%;
  min-height: 400px;
  padding: 14px;
  border: 1px solid #dcdfe6;
  border-radius: 4px;
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 14px;
  line-height: 1.7;
  resize: vertical;
  outline: none;
  transition: border-color 0.2s;
}

.content-editor:focus {
  border-color: #409eff;
}
</style>

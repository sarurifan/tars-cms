<template>
  <div class="site-config-page page-container">
    <el-form :model="form" label-width="140px" style="max-width: 700px" v-loading="loading">
      <el-divider content-position="left">基础信息</el-divider>

      <el-form-item label="站点名称">
        <el-input v-model="form.site_name" placeholder="tars-cms" />
      </el-form-item>

      <el-form-item label="站点标语">
        <el-input v-model="form.site_slogan" placeholder="用 TARS 构建的内容管理系统" />
      </el-form-item>

      <el-form-item label="站点域名">
        <el-input v-model="form.site_domain" placeholder="http://192.168.1.95:8200" />
      </el-form-item>

      <el-form-item label="备案号">
        <el-input v-model="form.icp" placeholder="可选" />
      </el-form-item>

      <el-divider content-position="left">联系信息</el-divider>

      <el-form-item label="联系邮箱">
        <el-input v-model="form.email" placeholder="可选" />
      </el-form-item>

      <el-form-item label="联系电话">
        <el-input v-model="form.phone" placeholder="可选" />
      </el-form-item>

      <el-divider content-position="left">功能开关</el-divider>

      <el-form-item label="开放注册">
        <el-switch v-model="form.allow_register" active-value="1" inactive-value="0" />
      </el-form-item>

      <el-form-item label="显示备案号">
        <el-switch v-model="form.show_icp" active-value="1" inactive-value="0" />
      </el-form-item>

      <el-form-item>
        <el-button type="primary" :loading="saving" @click="handleSave">保存配置</el-button>
        <el-button @click="fetchConfig">重置</el-button>
      </el-form-item>
    </el-form>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { getSiteConfig, updateSiteConfig } from '@/api/admin'

const loading = ref(false)
const saving = ref(false)

const form = reactive({
  site_name: '',
  site_slogan: '',
  site_domain: '',
  icp: '',
  email: '',
  phone: '',
  allow_register: '1',
  show_icp: '1'
})

async function fetchConfig() {
  loading.value = true
  try {
    const res: any = await getSiteConfig()
    if (res.code === 0) {
      const cfg = typeof res.data === 'string' ? JSON.parse(res.data) : res.data || {}
      Object.assign(form, cfg)
    }
  } catch (e) {
  } finally {
    loading.value = false
  }
}

async function handleSave() {
  saving.value = true
  try {
    const res: any = await updateSiteConfig({ ...form })
    if (res.code === 0) {
      ElMessage.success('配置已保存')
    }
  } catch (e) {
  } finally {
    saving.value = false
  }
}

onMounted(fetchConfig)
</script>

<style scoped>
.site-config-page {
  min-height: 500px;
}
</style>

<template>
  <div class="register-page">
    <div class="auth-card">
      <div class="auth-head">
        <h1 class="auth-title">注册 tars-cms</h1>
        <p class="auth-sub">已有账号？<router-link to="/login" class="auth-link">直接登录</router-link></p>
      </div>

      <form class="auth-form" @submit.prevent="handleRegister">
        <div class="form-item">
          <label class="form-label">用户名</label>
          <input
            v-model="form.username"
            class="form-input"
            type="text"
            placeholder="3-32 位字母数字"
            autocomplete="username"
            required
          />
        </div>

        <div class="form-item">
          <label class="form-label">邮箱（可选）</label>
          <input
            v-model="form.email"
            class="form-input"
            type="email"
            placeholder="用于找回密码"
            autocomplete="email"
          />
        </div>

        <div class="form-item">
          <label class="form-label">密码</label>
          <input
            v-model="form.password"
            class="form-input"
            type="password"
            placeholder="至少 6 位"
            autocomplete="new-password"
            required
          />
        </div>

        <div class="form-item">
          <label class="form-label">确认密码</label>
          <input
            v-model="form.confirm"
            class="form-input"
            type="password"
            placeholder="再输入一次"
            autocomplete="new-password"
            required
          />
        </div>

        <div class="form-error" v-if="errorMsg">{{ errorMsg }}</div>

        <button class="form-submit" type="submit" :disabled="loading">
          {{ loading ? '注册中…' : '注 册' }}
        </button>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { register } from '@/api/content'

const router = useRouter()
const loading = ref(false)
const errorMsg = ref('')

const form = reactive({
  username: '',
  email: '',
  password: '',
  confirm: ''
})

async function handleRegister() {
  errorMsg.value = ''
  if (!form.username || !form.password) {
    errorMsg.value = '请填写用户名和密码'
    return
  }
  if (form.password.length < 6) {
    errorMsg.value = '密码至少 6 位'
    return
  }
  if (form.password !== form.confirm) {
    errorMsg.value = '两次密码不一致'
    return
  }
  loading.value = true
  try {
    const res: any = await register({
      username: form.username,
      password: form.password,
      email: form.email || undefined
    })
    if (res.code === 0) {
      // 注册成功自动登录
      if (res.data?.token) {
        localStorage.setItem('h5_token', res.data.token)
        localStorage.setItem('h5_user', JSON.stringify(res.data.user || {}))
      }
      router.push('/')
    } else {
      errorMsg.value = res.msg || '注册失败'
    }
  } catch (e: any) {
    errorMsg.value = e.message || '注册失败，请重试'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.register-page {
  display: flex;
  justify-content: center;
  padding-top: 48px;
}

.auth-card {
  width: 100%;
  max-width: 420px;
  background: #fff;
  border-radius: var(--h5-radius-lg);
  padding: 36px 32px;
  box-shadow: var(--h5-shadow-lg);
}

.auth-head {
  text-align: center;
  margin-bottom: 30px;
}

.auth-title {
  font-size: 24px;
  font-weight: 750;
  color: var(--h5-text);
  margin-bottom: 8px;
}

.auth-sub {
  font-size: 14px;
  color: var(--h5-text-secondary);
}

.auth-link {
  color: var(--h5-primary);
}

.auth-form {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.form-item {
  display: flex;
  flex-direction: column;
  gap: 7px;
}

.form-label {
  font-size: 13.5px;
  font-weight: 600;
  color: var(--h5-text);
}

.form-input {
  height: 44px;
  padding: 0 14px;
  border: 1px solid var(--h5-border);
  border-radius: var(--h5-radius);
  font-size: 15px;
  color: var(--h5-text);
  outline: none;
  transition: border-color 0.15s;
}

.form-input:focus {
  border-color: var(--h5-primary);
}

.form-input::placeholder {
  color: var(--h5-text-tertiary);
}

.form-error {
  font-size: 13.5px;
  color: var(--h5-danger);
  background: #fff2f1;
  padding: 9px 13px;
  border-radius: var(--h5-radius-sm);
}

.form-submit {
  height: 46px;
  background: var(--h5-primary);
  color: #fff;
  border: none;
  border-radius: var(--h5-radius);
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.15s;
  margin-top: 4px;
}

.form-submit:hover:not(:disabled) {
  background: var(--h5-primary-dark);
}

.form-submit:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
</style>

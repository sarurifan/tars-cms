<template>
  <div class="login-page">
    <div class="auth-card">
      <div class="auth-head">
        <h1 class="auth-title">登录 tars-cms</h1>
        <p class="auth-sub">还没有账号？<router-link to="/register" class="auth-link">立即注册</router-link></p>
      </div>

      <form class="auth-form" @submit.prevent="handleLogin">
        <div class="form-item">
          <label class="form-label">用户名</label>
          <input
            v-model="form.username"
            class="form-input"
            type="text"
            placeholder="请输入用户名"
            autocomplete="username"
            required
          />
        </div>

        <div class="form-item">
          <label class="form-label">密码</label>
          <input
            v-model="form.password"
            class="form-input"
            type="password"
            placeholder="请输入密码"
            autocomplete="current-password"
            required
          />
        </div>

        <div class="form-error" v-if="errorMsg">{{ errorMsg }}</div>

        <button class="form-submit" type="submit" :disabled="loading">
          {{ loading ? '登录中…' : '登 录' }}
        </button>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { login } from '@/api/content'

const router = useRouter()
const loading = ref(false)
const errorMsg = ref('')

const form = reactive({
  username: '',
  password: ''
})

async function handleLogin() {
  if (!form.username || !form.password) {
    errorMsg.value = '请填写用户名和密码'
    return
  }
  loading.value = true
  errorMsg.value = ''
  try {
    const res: any = await login(form)
    if (res.code === 0) {
      localStorage.setItem('h5_token', res.data.token)
      localStorage.setItem('h5_user', JSON.stringify(res.data.user || {}))
      window.dispatchEvent(new Event('auth-changed'))
      router.push('/')
    } else {
      errorMsg.value = res.msg || '登录失败'
    }
  } catch (e: any) {
    errorMsg.value = e.message || '登录失败，请重试'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.login-page {
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
  gap: 18px;
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

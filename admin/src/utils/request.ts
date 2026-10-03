import axios from 'axios'
import { ElMessage } from 'element-plus'
import { getToken, clearToken } from './auth'

// 创建 axios 实例
const service = axios.create({
  baseURL: '/api',
  timeout: 30000
})

// 请求拦截器
service.interceptors.request.use(
  (config) => {
    const token = getToken()
    if (token) {
      config.headers['Authorization'] = 'Bearer ' + token
    }
    return config
  },
  (error) => Promise.reject(error)
)

// 响应拦截器
service.interceptors.response.use(
  (response) => {
    const res = response.data
    // 二进制流直接返回
    if (response.config.responseType === 'blob') {
      return response
    }
    // 业务错误
    if (res.code !== 0) {
      ElMessage.error(res.msg || '请求失败')
      // 401 未登录
      if (res.code === 401 || (res.data && res.data.code === 401)) {
        clearToken()
        window.location.href = '/login'
      }
      return Promise.reject(new Error(res.msg || '请求失败'))
    }
    return res
  },
  (error) => {
    ElMessage.error(error.message || '网络错误')
    return Promise.reject(error)
  }
)

export default service

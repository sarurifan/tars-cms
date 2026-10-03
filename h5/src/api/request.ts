import axios from 'axios'

// h5 专属 axios 实例（独立于 admin，绝不复用）
const service = axios.create({
  baseURL: '/api',
  timeout: 20000
})

// 请求拦截器：自动携带 token
service.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('h5_token')
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
    if (res.code !== 0) {
      // token 过期
      if (res.code === 401) {
        localStorage.removeItem('h5_token')
        localStorage.removeItem('h5_user')
        window.location.href = '/login'
      }
      return Promise.reject(new Error(res.msg || '请求失败'))
    }
    return res
  },
  (error) => {
    return Promise.reject(error)
  }
)

export default service

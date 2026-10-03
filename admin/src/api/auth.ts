import request from '@/utils/request'

// ============ 认证接口 ============

export function login(data: { username: string; password: string; tenantId?: number }) {
  return request.post('/auth/login', { tenantId: 1, ...data })
}

export function register(data: {
  username: string
  password: string
  email?: string
  tenantId?: number
}) {
  return request.post('/auth/register', { tenantId: 1, ...data })
}

export function getUserInfo(tenantId = 1) {
  return request.get('/auth/userinfo', { params: { tenantId } })
}

export function logout(tenantId = 1) {
  return request.post('/auth/logout', null, { params: { tenantId } })
}

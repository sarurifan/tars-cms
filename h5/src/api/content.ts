import request from './request'

// ============ h5 内容接口（独立 API 层，不复用 admin） ============

/** 首页聚合 */
export function getHome(tenantId = 1) {
  return request.get('/cms/home', { params: { tenantId } })
}

/** 分类树 */
export function getCategoryTree(tenantId = 1) {
  return request.get('/cms/categories/tree', { params: { tenantId } })
}

/** 分类列表 */
export function getCategories(tenantId = 1) {
  return request.get('/cms/categories', { params: { tenantId } })
}

/** 文章列表（分页） */
export function getArticles(params: {
  categoryId?: number
  keyword?: string
  page?: number
  size?: number
  tenantId?: number
}) {
  return request.get('/cms/articles', { params: { tenantId: 1, ...params } })
}

/** 文章详情 */
export function getArticleDetail(id: number, tenantId = 1) {
  return request.get(`/cms/articles/${id}`, { params: { tenantId } })
}

/** 站点配置 */
export function getSiteConfig(tenantId = 1) {
  return request.get('/cms/config', { params: { tenantId } })
}

// ============ 认证 ============

export function login(data: { username: string; password: string }) {
  return request.post('/auth/login', { tenantId: 1, ...data })
}

export function register(data: { username: string; password: string; email?: string }) {
  return request.post('/auth/register', { tenantId: 1, ...data })
}

export function getUserInfo(tenantId = 1) {
  return request.get('/auth/userinfo', { params: { tenantId } })
}

export function logout(tenantId = 1) {
  return request.post('/auth/logout', null, { params: { tenantId } })
}

import request from '@/utils/request'

// ============ 后台管理接口 ============

// -------- 文章 --------

export function getAdminArticles(params: {
  tenantId?: number
  categoryId?: number
  status?: number
  page?: number
  size?: number
}) {
  return request.get('/admin/articles', { params: { tenantId: 1, ...params } })
}

export function createArticle(data: Record<string, any>) {
  return request.post('/admin/articles', { tenantId: 1, ...data })
}

export function updateArticle(id: number, data: Record<string, any>) {
  return request.put(`/admin/articles/${id}`, { tenantId: 1, ...data })
}

export function deleteArticle(id: number, tenantId = 1) {
  return request.delete(`/admin/articles/${id}`, { params: { tenantId } })
}

// -------- 分类 --------

export function getAdminCategories(tenantId = 1) {
  return request.get('/admin/categories', { params: { tenantId } })
}

export function createCategory(data: Record<string, any>) {
  return request.post('/admin/categories', { tenantId: 1, ...data })
}

export function updateCategory(id: number, data: Record<string, any>) {
  return request.put(`/admin/categories/${id}`, { tenantId: 1, ...data })
}

export function deleteCategory(id: number, tenantId = 1) {
  return request.delete(`/admin/categories/${id}`, { params: { tenantId } })
}

// -------- 成员 --------

export function getAdminMembers(tenantId = 1) {
  return request.get('/admin/members', { params: { tenantId } })
}

export function createMember(data: Record<string, any>) {
  return request.post('/admin/members', { tenantId: 1, ...data })
}

export function updateMember(id: number, data: Record<string, any>) {
  return request.put(`/admin/members/${id}`, { tenantId: 1, ...data })
}

export function deleteMember(id: number, tenantId = 1) {
  return request.delete(`/admin/members/${id}`, { params: { tenantId } })
}

// -------- 媒体 --------

export function getAdminMedia(params: { tenantId?: number; page?: number; size?: number }) {
  return request.get('/admin/media', { params: { tenantId: 1, ...params } })
}

// -------- 站点配置 --------

export function getSiteConfig(tenantId = 1) {
  return request.get('/admin/config', { params: { tenantId } })
}

export function updateSiteConfig(config: Record<string, string>, tenantId = 1) {
  return request.put('/admin/config', config, { params: { tenantId } })
}

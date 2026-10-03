import request from '@/utils/request'

// ============ 公开接口（内容站） ============

/** 首页聚合：banners / topArticles / focusArticles / latest / categories / config */
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
  tenantId?: number
  categoryId?: number
  keyword?: string
  page?: number
  size?: number
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

// utils/api.js — 内容接口（对应 h5/src/api/content.ts）
// 演示项目：所有请求走网关，与 h5 端接口一致
// 原生小程序使用 CommonJS（module.exports），不能用 ES module export
const app = getApp();

// 封装请求
function request(path, options = {}) {
  const { baseUrl, tenantId, token } = app.globalData;
  const header = {
    'Content-Type': 'application/json',
    ...(options.header || {})
  };
  // 已登录则带 token（cms 体系用 Authorization: Bearer）
  if (token) {
    header['Authorization'] = 'Bearer ' + token;
  }

  return new Promise((resolve, reject) => {
    wx.request({
      url: `${baseUrl}${path}`,
      method: options.method || 'GET',
      data: options.data || { tenantId },
      header,
      success(res) {
        resolve(res.data);
      },
      fail(err) {
        reject(err);
      }
    });
  });
}

module.exports = {
  // ============ 内容 ============

  /** 首页聚合 */
  getHome() {
    return request('/api/cms/home');
  },

  /** 分类树 */
  getCategoryTree() {
    return request('/api/cms/categories/tree');
  },

  /** 分类列表 */
  getCategories() {
    return request('/api/cms/categories');
  },

  /** 文章列表（分页） */
  getArticles({ categoryId = 0, keyword = '', page = 1, size = 10 } = {}) {
    return request('/api/cms/articles', {
      data: { tenantId: 1, categoryId, keyword, page, size }
    });
  },

  /** 文章详情 */
  getArticleDetail(id) {
    return request(`/api/cms/articles/${id}`);
  },

  /** 站点配置 */
  getSiteConfig() {
    return request('/api/cms/config');
  },

  // ============ 认证 ============

  login(data) {
    return request('/api/auth/login', {
      method: 'POST',
      data: { tenantId: 1, ...data }
    });
  },

  register(data) {
    return request('/api/auth/register', {
      method: 'POST',
      data: { tenantId: 1, ...data }
    });
  },

  getUserInfo() {
    return request('/api/auth/userinfo');
  },

  logout() {
    return request('/api/auth/logout', { method: 'POST' });
  },

  // ============ 微信登录 ============

  /**
   * 微信一键登录：wx.login 拿 code → 后端换 openid → 签发 cms token
   * @returns {Promise<{code, msg, data: {token, expires_at, user}}>}
   */
  wxLogin(jsCode, appid = '') {
    return request('/api/wx/ma/login', {
      method: 'POST',
      data: { tenantId: 1, appid, code: jsCode }
    });
  }
};

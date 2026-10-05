// app.js — tars-cms 小程序全局入口
// 演示项目：内容与 h5 端一致（文档 + 介绍）
App({
  globalData: {
    // 网关地址：小程序请求必须走网关（Host: cms 路由规则）
    baseUrl: 'http://192.168.1.95:8200',
    tenantId: 1,
    // 登录态（wx.login → /api/wx/ma/login 签发的 cms token）
    token: '',
    user: null
  },

  onLaunch() {
    // 从本地缓存恢复登录态
    const token = wx.getStorageSync('cms_token');
    const user = wx.getStorageSync('cms_user');
    if (token) {
      this.globalData.token = token;
      this.globalData.user = user || null;
    }
    console.log('[tars-cms] 小程序启动，网关:', this.globalData.baseUrl,
      '登录态:', token ? '已登录' : '未登录');
  },

  // 保存登录态（wxLogin 成功后调用）
  setLogin({ token, user }) {
    this.globalData.token = token || '';
    this.globalData.user = user || null;
    if (token) {
      wx.setStorageSync('cms_token', token);
      wx.setStorageSync('cms_user', user);
    } else {
      wx.removeStorageSync('cms_token');
      wx.removeStorageSync('cms_user');
    }
  },

  // 清除登录态
  clearLogin() {
    this.globalData.token = '';
    this.globalData.user = null;
    wx.removeStorageSync('cms_token');
    wx.removeStorageSync('cms_user');
  },

  // 是否已登录
  isLoggedIn() {
    return !!this.globalData.token;
  }
});

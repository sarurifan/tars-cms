// pages/home/index.js — 首页逻辑（对应 h5 HomePage）
const api = require('../../utils/api');
const app = getApp();

Page({
  data: {
    loading: true,
    isLoggedIn: false,
    loginText: '登录',
    home: {
      banners: [],
      topArticles: [],
      focusArticles: [],
      latest: [],
      categories: [],
      config: {}
    }
  },

  onShow() {
    // 每次显示时刷新登录态（登录页返回后更新）
    const loggedIn = app.isLoggedIn();
    const u = app.globalData.user || {};
    this.setData({
      isLoggedIn: loggedIn,
      loginText: loggedIn ? (u.nickname || u.username || '已登录') : '登录'
    });
  },

  onLoad() {
    this.fetchHome();
  },

  onPullDownRefresh() {
    this.fetchHome().finally(() => {
      wx.stopPullDownRefresh();
    });
  },

  async fetchHome() {
    this.setData({ loading: true });
    try {
      const res = await api.getHome();
      if (res.code === 0) {
        this.setData({ home: { ...this.data.home, ...res.data } });
      } else {
        wx.showToast({ title: res.msg || '加载失败', icon: 'none' });
      }
    } catch (e) {
      console.error('[home] fetchHome error:', e);
      wx.showToast({ title: '网络错误', icon: 'none' });
    } finally {
      this.setData({ loading: false });
    }
  },

  goCategory(e) {
    const slug = e.currentTarget.dataset.slug || '';
    wx.navigateTo({ url: `/pages/category/index?slug=${slug}` });
  },

  goAllArticles() {
    wx.navigateTo({ url: '/pages/category/index' });
  },

  goProfile() {
    wx.navigateTo({ url: '/pages/profile/index' });
  }
});

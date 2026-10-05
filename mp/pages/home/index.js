// pages/home/index.js — 首页逻辑（对应 h5 HomePage）
const api = require('../../utils/api');

Page({
  data: {
    loading: true,
    home: {
      banners: [],
      topArticles: [],
      focusArticles: [],
      latest: [],
      categories: [],
      config: {}
    }
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
  }
});

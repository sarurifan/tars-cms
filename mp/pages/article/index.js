// pages/article/index.js — 文章详情逻辑（对应 h5 ArticlePage）
const api = require('../../utils/api');

Page({
  data: {
    loading: true,
    article: null
  },

  onLoad(options) {
    const id = parseInt(options.id || '0', 10);
    if (!id) {
      this.setData({ loading: false, article: null });
      return;
    }
    this.fetchDetail(id);
  },

  async fetchDetail(id) {
    this.setData({ loading: true });
    try {
      const res = await api.getArticleDetail(id);
      if (res.code === 0 && res.data) {
        const article = res.data;
        wx.setNavigationBarTitle({ title: article.title || '文章详情' });
        this.setData({ article });
      } else {
        this.setData({ article: null });
      }
    } catch (e) {
      console.error('[article] fetchDetail error:', e);
      this.setData({ article: null });
      wx.showToast({ title: '网络错误', icon: 'none' });
    } finally {
      this.setData({ loading: false });
    }
  },

  goHome() {
    wx.navigateBack({
      fail: () => wx.switchTab({ url: '/pages/home/index' })
    });
  },

  goCategory() {
    const slug = this.data.article && this.data.article.category
      ? (this.data.article.category.slug || this.data.article.category.id)
      : '';
    wx.navigateTo({ url: `/pages/category/index?slug=${slug}` });
  }
});

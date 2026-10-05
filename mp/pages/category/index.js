// pages/category/index.js — 分类页逻辑（对应 h5 CategoryPage）
const api = require('../../utils/api');

Page({
  data: {
    loading: true,
    list: [],
    categories: [],
    currentSlug: '',
    page: 1,
    size: 10,
    total: 0,
    totalPages: 1
  },

  onLoad(options) {
    const slug = options.slug || '';
    this.setData({ currentSlug: slug });
    this.loadCategories();
    this.fetchList();
  },

  async loadCategories() {
    try {
      const res = await api.getCategories();
      if (res.code === 0) {
        this.setData({ categories: res.data || [] });
      }
    } catch (e) {
      console.error('[category] loadCategories error:', e);
    }
  },

  async fetchList() {
    this.setData({ loading: true });
    try {
      // slug → categoryId
      let categoryId = 0;
      if (this.data.currentSlug) {
        const cat = this.data.categories.find(c => c.slug === this.data.currentSlug);
        categoryId = cat ? cat.id : 0;
      }

      const res = await api.getArticles({
        categoryId,
        page: this.data.page,
        size: this.data.size
      });

      if (res.code === 0) {
        const d = res.data || {};
        const total = d.total || 0;
        this.setData({
          // 后端返回 data.list（PageList.List），不是 records
          list: d.list || [],
          total,
          totalPages: Math.max(1, Math.ceil(total / this.data.size))
        });
      } else {
        wx.showToast({ title: res.msg || '加载失败', icon: 'none' });
      }
    } catch (e) {
      console.error('[category] fetchList error:', e);
      wx.showToast({ title: '网络错误', icon: 'none' });
    } finally {
      this.setData({ loading: false });
    }
  },

  onFilter(e) {
    const slug = e.currentTarget.dataset.slug || '';
    this.setData({ currentSlug: slug, page: 1 });
    this.fetchList();
  },

  prevPage() {
    if (this.data.page > 1) {
      this.setData({ page: this.data.page - 1 });
      this.fetchList();
      wx.pageScrollTo({ scrollTop: 0, duration: 200 });
    }
  },

  nextPage() {
    if (this.data.page * this.data.size < this.data.total) {
      this.setData({ page: this.data.page + 1 });
      this.fetchList();
      wx.pageScrollTo({ scrollTop: 0, duration: 200 });
    }
  },

  goHome() {
    wx.navigateBack({ fail: () => wx.switchTab({ url: '/pages/home/index' }) });
  }
});

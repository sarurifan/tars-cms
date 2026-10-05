// components/article-card/index.js — 文章卡片逻辑
Component({
  properties: {
    data: {
      type: Object,
      value: {}
    }
  },

  methods: {
    onTap() {
      const id = this.data.data.id;
      if (id) {
        wx.navigateTo({
          url: `/pages/article/index?id=${id}`
        });
      }
    }
  }
});

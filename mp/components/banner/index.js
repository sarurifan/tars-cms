// components/banner/index.js
Component({
  properties: {
    banners: {
      type: Array,
      value: []
    }
  },

  methods: {
    onTap(e) {
      const id = e.currentTarget.dataset.id;
      if (id) {
        wx.navigateTo({ url: `/pages/article/index?id=${id}` });
      }
    }
  }
});

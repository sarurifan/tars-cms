// pages/profile/index.js — 我的（登录 + 用户信息）
const api = require('../../utils/api');
const app = getApp();

// 微信小程序 AppID（演示项目留空；填真实值即可在真机登录）
// 获取方式：微信公众平台 → 开发管理 → 开发设置 → AppID
const WX_APPID = '';

Page({
  data: {
    isLoggedIn: false,
    user: null,
    logging: false,
    avatarText: '微',
    appidMissing: false
  },

  onShow() {
    this.refreshLoginState();
  },

  refreshLoginState() {
    const loggedIn = app.isLoggedIn();
    const user = app.globalData.user || {};
    this.setData({
      isLoggedIn: loggedIn,
      user,
      avatarText: (user.nickname || user.username || '微').charAt(0),
      appidMissing: !WX_APPID
    });
  },

  // 微信一键登录
  doWxLogin() {
    if (this.data.logging) return;

    // 演示模式：未配置 AppID 时给提示，不发起真实请求
    if (!WX_APPID) {
      wx.showModal({
        title: '演示模式',
        content: '未配置小程序 AppID。\n\n填入真实 AppID 后，此按钮将调用 wx.login 完成微信一键登录。',
        showCancel: false,
        confirmText: '知道了'
      });
      return;
    }

    this.setData({ logging: true });
    wx.showLoading({ title: '登录中…' });

    wx.login({
      success: async (res) => {
        if (!res.code) {
          wx.hideLoading();
          this.setData({ logging: false });
          wx.showToast({ title: 'wx.login 失败', icon: 'none' });
          return;
        }
        try {
          const result = await api.wxLogin(res.code, WX_APPID);
          wx.hideLoading();
          this.setData({ logging: false });
          if (result.code === 0 && result.data && result.data.token) {
            app.setLogin({
              token: result.data.token,
              user: result.data.user
            });
            this.refreshLoginState();
            wx.showToast({ title: '登录成功', icon: 'success' });
          } else {
            wx.showToast({ title: result.msg || '登录失败', icon: 'none' });
          }
        } catch (e) {
          wx.hideLoading();
          this.setData({ logging: false });
          wx.showToast({ title: '网络错误', icon: 'none' });
        }
      },
      fail: () => {
        wx.hideLoading();
        this.setData({ logging: false });
        wx.showToast({ title: 'wx.login 调用失败', icon: 'none' });
      }
    });
  },

  doLogout() {
    wx.showModal({
      title: '退出登录',
      content: '确定退出当前账号吗？',
      success: (res) => {
        if (res.confirm) {
          app.clearLogin();
          this.refreshLoginState();
          wx.showToast({ title: '已退出', icon: 'none' });
        }
      }
    });
  },

  goAbout() {
    wx.navigateTo({ url: '/pages/about/index' });
  },

  goHome() {
    wx.navigateBack({ fail: () => wx.switchTab({ url: '/pages/home/index' }) });
  }
});

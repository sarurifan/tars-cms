// app.js — tars-cms 小程序全局入口
// 演示项目：内容与 h5 端一致（文档 + 介绍）
App({
  globalData: {
    // 网关地址：小程序请求必须走网关（Host: cms 路由规则）
    baseUrl: 'http://192.168.1.95:8200',
    tenantId: 1
  },

  onLaunch() {
    // 演示项目：控制台输出用于调试
    console.log('[tars-cms] 小程序启动，网关地址：', this.globalData.baseUrl);
  }
});

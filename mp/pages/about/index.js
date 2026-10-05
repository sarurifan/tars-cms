// pages/about/index.js — 关于项目（介绍页静态内容）
Page({
  data: {
    services: [
      { name: 'cms.CmsServer', desc: '内容服务 (Go, 13101/13102)' },
      { name: 'cms.CmsBff', desc: 'HTTP ⇄ TARS 转换 (3103)' },
      { name: 'cms.CmsWeb', desc: '静态站 + 上传 (13103)' },
      { name: 'wx.WxServer', desc: '微信核心 (Go, 13201/13202)' },
      { name: 'wx.WxBff', desc: '微信 BFF (3203)' },
      { name: 'TarsGateway', desc: '网关 (8200, Host 路由)' }
    ],
    wxApis: [
      { method: 'POST', path: '/api/wx/ma/code2session', desc: '小程序 code 换 openid（登录）' },
      { method: 'GET', path: '/api/wx/ma/token', desc: '小程序 access_token（中控）' },
      { method: 'POST', path: '/api/wx/ma/subscribe/send', desc: '订阅消息' },
      { method: 'GET', path: '/api/wx/mp/token', desc: '公众号 access_token（中控）' },
      { method: 'GET', path: '/api/wx/mp/userinfo', desc: '关注用户信息' },
      { method: 'POST', path: '/api/wx/mp/template/send', desc: '模板消息' },
      { method: 'GET', path: '/api/wx/verify', desc: '微信验签' }
    ]
  }
});

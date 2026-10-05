package main

import (
	"fmt"
	"os"

	"github.com/TarsCloud/TarsGo/tars"
	"github.com/tars-cms/wx/tars-protocol/wx"
)

// wx.WxServer 微信服务核心节点
//
// 【职责】
//   1. access_token 中控服务（统一拉取/刷新/缓存，防并发击穿）
//   2. 公众号能力：获取用户信息、模板消息、验签
//   3. 小程序能力：code2session 登录凭证校验、订阅消息
//
// 【架构】双端口 (与 cms.CmsServer 相同模式)
//   - adapter 13201 (protocol=tars)：MpObj + MaObj servant
//     tarsnode 用它探测心跳/注册
//   - adapter 13202 (protocol=http)：保留扩展

func main() {
	// 初始化数据库
	if _, err := InitDB(); err != nil {
		fmt.Fprintf(os.Stderr, "init wx db failed: %v\n", err)
		os.Exit(-1)
	}
	fmt.Println("wx database connected")

	cfg := tars.GetServerConfig()

	// 注册 MpObj (公众号)
	mpImp := new(mpServantImp)
	if err := mpImp.Init(); err != nil {
		fmt.Fprintf(os.Stderr, "mp imp init failed: %v\n", err)
		os.Exit(-1)
	}
	mpServant := wx.NewMpObj()
	mpServant.AddServantWithContext(mpImp, cfg.App+"."+cfg.Server+".MpObj")

	// 注册 MaObj (小程序)
	maImp := new(maServantImp)
	if err := maImp.Init(); err != nil {
		fmt.Fprintf(os.Stderr, "ma imp init failed: %v\n", err)
		os.Exit(-1)
	}
	maServant := wx.NewMaObj()
	maServant.AddServantWithContext(maImp, cfg.App+"."+cfg.Server+".MaObj")

	fmt.Println("wx server servants registered, starting...")
	tars.Run()
}

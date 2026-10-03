package main

import (
	"fmt"
	"os"

	"github.com/TarsCloud/TarsGo/tars"
	"github.com/tars-cms/cms/tars-protocol/cms"
)

// tars-cms 内容管理服务
//
// 【架构】单进程双端口（与 nerv.AuthServer 同一模式）
//   - adapter 13101 (protocol=tars)：ArticleObj + AuthObj servant
//     tarsnode 用它做存活探测/心跳/注册
//   - adapter 13102 (protocol=http)：静态文件 + 媒体文件下载
//     由 TarsGateway → BFF 转发业务接口到这里
//
// 【业务接口】全部走 TarsGateway → BFF → 本服务 TARS adapter
// 前端不直接连本服务，统一经网关
//
// 【多租户】所有业务查询自动带 tenant_id 过滤（见 db.go Tenant/TenantTable）

func main() {
	// 初始化数据库
	if _, err := InitDB(); err != nil {
		fmt.Fprintf(os.Stderr, "init db failed: %v\n", err)
		os.Exit(-1)
	}
	fmt.Println("cms database connected")

	cfg := tars.GetServerConfig()

	// 注册业务 servant：ArticleObj
	articleImp := new(articleServantImp)
	if err := articleImp.Init(); err != nil {
		fmt.Fprintf(os.Stderr, "article imp init failed: %v\n", err)
		os.Exit(-1)
	}
	articleServant := cms.NewArticleObj()
	articleServant.AddServantWithContext(articleImp, cfg.App+"."+cfg.Server+".ArticleObj")

	// 注册业务 servant：AuthObj
	authImp := new(authServantImp)
	if err := authImp.Init(); err != nil {
		fmt.Fprintf(os.Stderr, "auth imp init failed: %v\n", err)
		os.Exit(-1)
	}
	authServant := cms.NewAuthObj()
	authServant.AddServantWithContext(authImp, cfg.App+"."+cfg.Server+".AuthObj")

	// 运行 tars 框架（阻塞）
	tars.Run()
}

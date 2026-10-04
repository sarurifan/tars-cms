package main

import (
	"fmt"
	"os"
	"sync"
	"time"

	"gorm.io/driver/mysql"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
	"gorm.io/gorm/schema"
)

// ============ 数据库连接（单例 + 多租户 Scope） ============

var (
	dbOnce sync.Once
	dbInst *gorm.DB
	dbErr  error
)

// InitDB 初始化数据库连接
//
// 连接参数优先从环境变量读取，其次使用默认值（tars 网络内 MySQL）。
// 环境变量：
//
//	CMS_DB_HOST (默认 172.25.0.2)
//	CMS_DB_PORT (默认 3306)
//	CMS_DB_USER (默认 root)
//	CMS_DB_PASS (默认空)
//	CMS_DB_NAME (默认 tars_cms)
func InitDB() (*gorm.DB, error) {
	dbOnce.Do(func() {
		host := envOr("CMS_DB_HOST", "172.25.0.2")
		port := envOr("CMS_DB_PORT", "3306")
		user := envOr("CMS_DB_USER", "root")
		// 密码不设默认值：必须由环境变量提供，避免凭据进仓库
		pass := os.Getenv("CMS_DB_PASS")
		if pass == "" {
			dbErr = fmt.Errorf("环境变量 CMS_DB_PASS 未设置（数据库密码不可硬编码）")
			return
		}
		name := envOr("CMS_DB_NAME", "tars_cms")

		dsn := fmt.Sprintf(
			"%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local",
			user, pass, host, port, name,
		)

		dbInst, dbErr = gorm.Open(mysql.Open(dsn), &gorm.Config{
			Logger: logger.Default.LogMode(logger.Warn),
			NamingStrategy: schema.NamingStrategy{
				SingularTable: true, // 表名不加复数
			},
			NowFunc: func() time.Time {
				return time.Now().Local()
			},
		})
		if dbErr != nil {
			return
		}

		// 连接池
		sqlDB, err := dbInst.DB()
		if err == nil {
			sqlDB.SetMaxIdleConns(10)
			sqlDB.SetMaxOpenConns(100)
			sqlDB.SetConnMaxLifetime(time.Hour)
		}
	})
	return dbInst, dbErr
}

// DB 获取全局连接
func DB() *gorm.DB {
	if dbInst == nil {
		if _, err := InitDB(); err != nil {
			panic("database not initialized: " + err.Error())
		}
	}
	return dbInst
}

// Tenant 租户作用域：所有业务查询自动带 tenant_id 过滤
//
// 用法：Tenant(tid).Where("status = ?", 1).Find(&list)
// 业务代码无需在每处手写 WHERE tenant_id = ?
func Tenant(tenantID int32) *gorm.DB {
	return DB().Where("tenant_id = ?", tenantID)
}

// TenantTable 指定表 + 租户作用域（链式起点）
func TenantTable(tenantID int32, model interface{}) *gorm.DB {
	return DB().Model(model).Where("tenant_id = ?", tenantID)
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

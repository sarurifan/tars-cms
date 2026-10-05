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

var (
	dbOnce sync.Once
	dbInst *gorm.DB
	dbErr  error
)

// InitDB 初始化微信节点数据库连接 (tars_wx)
func InitDB() (*gorm.DB, error) {
	dbOnce.Do(func() {
		host := envOr("CMS_DB_HOST", "172.25.0.2")
		port := envOr("CMS_DB_PORT", "3306")
		user := envOr("CMS_DB_USER", "root")
		pass := os.Getenv("CMS_DB_PASS")
		if pass == "" {
			dbErr = fmt.Errorf("环境变量 CMS_DB_PASS 未设置（数据库密码不可硬编码）")
			return
		}
		// 独立库 tars_wx
		name := envOr("WX_DB_NAME", "tars_wx")

		dsn := fmt.Sprintf(
			"%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local",
			user, pass, host, port, name,
		)

		dbInst, dbErr = gorm.Open(mysql.Open(dsn), &gorm.Config{
			Logger: logger.Default.LogMode(logger.Warn),
			NamingStrategy: schema.NamingStrategy{
				SingularTable: true,
			},
			NowFunc: func() time.Time {
				return time.Now().Local()
			},
		})
		if dbErr != nil {
			return
		}

		sqlDB, err := dbInst.DB()
		if err == nil {
			sqlDB.SetMaxIdleConns(5)
			sqlDB.SetMaxOpenConns(50)
			sqlDB.SetConnMaxLifetime(time.Hour)
		}
	})
	return dbInst, dbErr
}

func DB() *gorm.DB {
	if dbInst == nil {
		if _, err := InitDB(); err != nil {
			panic("wx database not initialized: " + err.Error())
		}
	}
	return dbInst
}

func Tenant(tenantID int32) *gorm.DB {
	return DB().Where("tenant_id = ?", tenantID)
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

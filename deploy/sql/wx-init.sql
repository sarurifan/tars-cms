-- ============================================================
-- tars-wx 数据库初始化
-- 数据库: tars_wx
-- 字符集: utf8mb4 (支持 emoji)
-- 多租户: 所有业务表带 tenant_id
-- ============================================================

CREATE DATABASE IF NOT EXISTS `tars_wx`
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

USE `tars_wx`;

-- ------------------------------------------------------------
-- 1. 微信账号配置表（公众号 + 小程序）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `wx_account` (
    `id`                BIGINT       NOT NULL AUTO_INCREMENT,
    `tenant_id`         INT          NOT NULL DEFAULT 1      COMMENT '租户ID',
    `app_type`          VARCHAR(16)  NOT NULL DEFAULT 'mp'   COMMENT 'mp 公众号 / ma 小程序',
    `appid`             VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '微信 AppID',
    `app_secret`        VARCHAR(128) NOT NULL DEFAULT ''     COMMENT '微信 AppSecret',
    `token`             VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '服务器配置 Token',
    `encoding_aes_key`  VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '消息加解密密钥 (43位)',
    `name`              VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '账号名称',
    `status`            TINYINT      NOT NULL DEFAULT 1      COMMENT '0禁用 1启用',
    `created_at`        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_appid` (`appid`),
    KEY `idx_tenant_type` (`tenant_id`, `app_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='微信账号配置表';

-- ------------------------------------------------------------
-- 2. access_token 中控缓存表
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `wx_access_token` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT,
    `appid`      VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '微信 AppID',
    `token`      VARCHAR(512) NOT NULL DEFAULT ''     COMMENT '接口调用凭证 (微信官方要求>=512)',
    `expires_at` DATETIME     NOT NULL                COMMENT '过期绝对时间',
    `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_appid` (`appid`),
    KEY `idx_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='access_token中控缓存表';

-- ------------------------------------------------------------
-- 3. 微信用户表（公众号粉丝 / 小程序用户）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `wx_user` (
    `id`          BIGINT       NOT NULL AUTO_INCREMENT,
    `tenant_id`   INT          NOT NULL DEFAULT 1      COMMENT '租户ID',
    `appid`       VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '来源 AppID',
    `openid`      VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '用户 OpenID',
    `unionid`     VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '跨应用 UnionID',
    `nickname`    VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '昵称',
    `avatar`      VARCHAR(255) NOT NULL DEFAULT ''     COMMENT '头像URL',
    `gender`      TINYINT      NOT NULL DEFAULT 0      COMMENT '0未知 1男 2女',
    `city`        VARCHAR(32)  NOT NULL DEFAULT ''     COMMENT '城市',
    `province`    VARCHAR(32)  NOT NULL DEFAULT ''     COMMENT '省份',
    `country`     VARCHAR(32)  NOT NULL DEFAULT ''     COMMENT '国家',
    `subscribe`   TINYINT      NOT NULL DEFAULT 0      COMMENT '公众号关注状态: 0未关注 1已关注',
    `session_key` VARCHAR(128) NOT NULL DEFAULT ''     COMMENT '小程序 session_key (严禁返回前端)',
    `cms_user_id` BIGINT       NOT NULL DEFAULT 0      COMMENT '绑定的 tars_cms.users.id',
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_app_openid` (`appid`, `openid`),
    KEY `idx_unionid` (`unionid`),
    KEY `idx_tenant` (`tenant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='微信用户表';

-- ------------------------------------------------------------
-- 4. 消息记录表（模板消息 / 订阅消息 / 用户发信）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `wx_message` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT,
    `tenant_id`  INT          NOT NULL DEFAULT 1      COMMENT '租户ID',
    `appid`      VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '微信 AppID',
    `msg_type`   VARCHAR(32)  NOT NULL DEFAULT ''     COMMENT 'template_msg/subscribe_msg/text/event',
    `direction`  VARCHAR(8)   NOT NULL DEFAULT 'out'  COMMENT 'in 接收 / out 发送',
    `from_user`  VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '发送者',
    `to_user`    VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '接收者 (OpenID)',
    `content`    TEXT                                 COMMENT '消息内容 JSON',
    `status`     VARCHAR(16)  NOT NULL DEFAULT 'sent' COMMENT 'sent/success/failed',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_app_user` (`appid`, `to_user`),
    KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='微信消息记录表';

-- ------------------------------------------------------------
-- 5. 测试账号占位数据（幂等插入，appid 唯一键 + INSERT IGNORE）
-- ------------------------------------------------------------
INSERT IGNORE INTO `wx_account` (`tenant_id`, `app_type`, `appid`, `app_secret`, `token`, `encoding_aes_key`, `name`, `status`)
VALUES (1, 'mp', 'wx_test_mp_demo', 'secret_demo_mp_123456', 'tars_token_2026', 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', '测试公众号', 1);

INSERT IGNORE INTO `wx_account` (`tenant_id`, `app_type`, `appid`, `app_secret`, `token`, `encoding_aes_key`, `name`, `status`)
VALUES (1, 'ma', 'wx_test_ma_demo', 'secret_demo_ma_123456', '', '', '测试小程序', 1);

-- ============================================================
-- tars-cms 数据库初始化
-- 数据库: tars_cms
-- 字符集: utf8mb4 (支持 emoji)
-- 多租户: 所有业务表带 tenant_id
-- ============================================================

CREATE DATABASE IF NOT EXISTS `tars_cms`
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

USE `tars_cms`;

-- ------------------------------------------------------------
-- 租户表
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cms_tenant` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT,
    `name`       VARCHAR(100) NOT NULL DEFAULT ''   COMMENT '租户名称',
    `code`       VARCHAR(50)  NOT NULL DEFAULT ''   COMMENT '租户标识',
    `status`     TINYINT      NOT NULL DEFAULT 1    COMMENT '0禁用 1启用',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='租户表';

-- ------------------------------------------------------------
-- 分类表（树形，最多三级）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cms_category` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT,
    `tenant_id`  BIGINT       NOT NULL DEFAULT 0    COMMENT '租户ID',
    `pid`        BIGINT       NOT NULL DEFAULT 0    COMMENT '父分类ID，0=顶级',
    `name`       VARCHAR(100) NOT NULL DEFAULT ''   COMMENT '分类名称',
    `slug`       VARCHAR(100) NOT NULL DEFAULT ''   COMMENT 'URL别名',
    `sort`       INT          NOT NULL DEFAULT 0    COMMENT '排序，越小越前',
    `status`     TINYINT      NOT NULL DEFAULT 1    COMMENT '0禁用 1启用',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_tenant_pid` (`tenant_id`, `pid`),
    KEY `idx_tenant_sort` (`tenant_id`, `sort`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='分类表';

-- ------------------------------------------------------------
-- 文章主表（列表用，不含正文）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cms_article` (
    `id`          BIGINT       NOT NULL AUTO_INCREMENT,
    `tenant_id`   BIGINT       NOT NULL DEFAULT 0    COMMENT '租户ID',
    `title`       VARCHAR(255) NOT NULL DEFAULT ''   COMMENT '标题',
    `slug`        VARCHAR(255) NOT NULL DEFAULT ''   COMMENT 'URL别名',
    `summary`     VARCHAR(500) NOT NULL DEFAULT ''   COMMENT '摘要',
    `cover`       VARCHAR(500) NOT NULL DEFAULT ''   COMMENT '封面图',
    `category_id` BIGINT       NOT NULL DEFAULT 0    COMMENT '分类ID',
    `is_banner`   TINYINT      NOT NULL DEFAULT 0    COMMENT '是否轮播图',
    `is_top`      TINYINT      NOT NULL DEFAULT 0    COMMENT '是否置顶',
    `is_focus`    TINYINT      NOT NULL DEFAULT 0    COMMENT '是否焦点',
    `sort`        INT          NOT NULL DEFAULT 0    COMMENT '排序，越小越前',
    `type`        VARCHAR(20)  NOT NULL DEFAULT 'article' COMMENT 'article/tutorial/doc/news',
    `author_id`   BIGINT       NOT NULL DEFAULT 0    COMMENT '作者ID',
    `source`      VARCHAR(255) NOT NULL DEFAULT ''   COMMENT '来源',
    `view_count`  BIGINT       NOT NULL DEFAULT 0    COMMENT '浏览量',
    `status`      TINYINT      NOT NULL DEFAULT 0    COMMENT '0草稿 1发布 2归档',
    `publish_at`  DATETIME     NULL                  COMMENT '发布时间',
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `deleted_at`  DATETIME     NULL                  COMMENT '软删除时间',
    PRIMARY KEY (`id`),
    KEY `idx_tenant_cat` (`tenant_id`, `category_id`),
    KEY `idx_tenant_status` (`tenant_id`, `status`),
    KEY `idx_tenant_sort` (`tenant_id`, `sort`),
    KEY `idx_tenant_publish` (`tenant_id`, `publish_at`),
    KEY `idx_deleted` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='文章主表';

-- ------------------------------------------------------------
-- 文章正文表（大字段分离，性能关键）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cms_article_body` (
    `article_id` BIGINT   NOT NULL                COMMENT '文章ID',
    `tenant_id`  BIGINT   NOT NULL DEFAULT 0      COMMENT '租户ID',
    `body`       MEDIUMTEXT                       COMMENT '富文本HTML正文',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`article_id`),
    KEY `idx_tenant` (`tenant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='文章正文表';

-- ------------------------------------------------------------
-- 站点配置表（KV）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cms_config` (
    `id`           BIGINT       NOT NULL AUTO_INCREMENT,
    `tenant_id`    BIGINT       NOT NULL DEFAULT 0  COMMENT '租户ID',
    `config_key`   VARCHAR(100) NOT NULL DEFAULT '' COMMENT '配置键',
    `config_value` TEXT                             COMMENT '配置值',
    `group_name`   VARCHAR(50)  NOT NULL DEFAULT 'site' COMMENT '分组',
    `remark`       VARCHAR(255) NOT NULL DEFAULT '' COMMENT '备注',
    `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_tenant_key` (`tenant_id`, `config_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='站点配置表';

-- ------------------------------------------------------------
-- 成员表
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cms_member` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT,
    `tenant_id`  BIGINT       NOT NULL DEFAULT 0  COMMENT '租户ID',
    `name`       VARCHAR(100) NOT NULL DEFAULT '' COMMENT '姓名',
    `avatar`     VARCHAR(500) NOT NULL DEFAULT '' COMMENT '头像',
    `title`      VARCHAR(100) NOT NULL DEFAULT '' COMMENT '职务',
    `bio`        TEXT                             COMMENT '简介',
    `role`       VARCHAR(50)  NOT NULL DEFAULT '' COMMENT '角色',
    `sort`       INT          NOT NULL DEFAULT 0  COMMENT '排序',
    `status`     TINYINT      NOT NULL DEFAULT 1  COMMENT '0禁用 1启用',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_tenant_sort` (`tenant_id`, `sort`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='成员表';

-- ------------------------------------------------------------
-- 媒体文件表
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cms_media` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT,
    `tenant_id`  BIGINT       NOT NULL DEFAULT 0  COMMENT '租户ID',
    `name`       VARCHAR(255) NOT NULL DEFAULT '' COMMENT '原始文件名',
    `path`       VARCHAR(500) NOT NULL DEFAULT '' COMMENT '存储路径',
    `url`        VARCHAR(500) NOT NULL DEFAULT '' COMMENT '访问URL',
    `size`       BIGINT       NOT NULL DEFAULT 0  COMMENT '文件大小(字节)',
    `mime`       VARCHAR(100) NOT NULL DEFAULT '' COMMENT 'MIME类型',
    `driver`     VARCHAR(20)  NOT NULL DEFAULT 'local' COMMENT 'local/oss',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_tenant` (`tenant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='媒体文件表';

-- ------------------------------------------------------------
-- 用户表
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `users` (
    `id`            BIGINT       NOT NULL AUTO_INCREMENT,
    `tenant_id`     BIGINT       NOT NULL DEFAULT 0  COMMENT '租户ID',
    `username`      VARCHAR(50)  NOT NULL DEFAULT '' COMMENT '用户名',
    `email`         VARCHAR(100) NOT NULL DEFAULT '' COMMENT '邮箱',
    `password_hash` VARCHAR(255) NOT NULL DEFAULT '' COMMENT 'bcrypt哈希',
    `nickname`      VARCHAR(50)  NOT NULL DEFAULT '' COMMENT '昵称',
    `avatar`        VARCHAR(500) NOT NULL DEFAULT '' COMMENT '头像',
    `role`          VARCHAR(20)  NOT NULL DEFAULT 'user' COMMENT 'user/editor/admin',
    `status`        TINYINT      NOT NULL DEFAULT 1  COMMENT '0禁用 1启用',
    `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_tenant_username` (`tenant_id`, `username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';

-- ------------------------------------------------------------
-- 会话表（token）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cms_session` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT,
    `tenant_id`  BIGINT       NOT NULL DEFAULT 0  COMMENT '租户ID',
    `user_id`    BIGINT       NOT NULL DEFAULT 0  COMMENT '用户ID',
    `token`      VARCHAR(128) NOT NULL DEFAULT '' COMMENT '访问令牌',
    `expires_at` DATETIME     NOT NULL            COMMENT '过期时间',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_token` (`token`),
    KEY `idx_tenant_user` (`tenant_id`, `user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='会话表';

-- ============================================================
-- 初始数据
-- ============================================================

-- 默认租户
INSERT INTO `cms_tenant` (`id`, `name`, `code`, `status`)
VALUES (1, '默认租户', 'default', 1)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

-- 站点配置（默认值）
INSERT INTO `cms_config` (`tenant_id`, `config_key`, `config_value`, `group_name`, `remark`) VALUES
    (1, 'site_name',    'tars-cms',                          'site', '站点名称'),
    (1, 'site_logo',    '',                                  'site', '站点Logo'),
    (1, 'site_desc',    '基于 TARS 的开源内容管理系统',        'site', '站点描述'),
    (1, 'site_keywords','TARS,CMS,微服务,Go',                 'site', 'SEO关键词'),
    (1, 'copyright',    '© 2026 tars-cms · GPL v3.0',        'site', '版权信息'),
    (1, 'icp',          '',                                  'site', '备案号'),
    (1, 'contact',      '',                                  'site', '联系方式'),
    (1, 'upload_driver','local',                             'upload', '上传驱动 local/oss'),
    (1, 'oss_bucket',   '',                                  'upload', 'OSS Bucket'),
    (1, 'oss_endpoint', '',                                  'upload', 'OSS Endpoint')
ON DUPLICATE KEY UPDATE `config_value` = VALUES(`config_value`);

-- 默认分类（演示用，tars-cms 自己的文档站结构）
-- 幂等：同一租户下同名分类已存在则跳过（cms_category 无业务唯一键，用 NOT EXISTS 守）
INSERT INTO `cms_category` (`tenant_id`, `pid`, `name`, `slug`, `sort`, `status`)
SELECT * FROM (
    SELECT 1 AS tenant_id, 0 AS pid, '快速开始' AS name, 'getting-started' AS slug, 10 AS sort, 1 AS status
    UNION ALL SELECT 1, 0, '核心概念', 'concepts',  20, 1
    UNION ALL SELECT 1, 0, '实战教程', 'tutorials', 30, 1
    UNION ALL SELECT 1, 0, '部署运维', 'deploy',    40, 1
    UNION ALL SELECT 1, 0, '关于项目', 'about',     50, 1
) AS seed
WHERE NOT EXISTS (
    SELECT 1 FROM `cms_category` c
    WHERE c.`tenant_id` = seed.tenant_id AND c.`name` = seed.name
);

-- 默认管理员账号: admin / admin123
-- bcrypt hash of "admin123" (cost=10)
INSERT INTO `users` (`tenant_id`, `username`, `email`, `password_hash`, `nickname`, `role`, `status`)
VALUES (1, 'admin', 'admin@tars-cms.local',
        '$2a$10$xVKpbPZ7JjdcLbjuHhb.N.mPPwPMfzThseb7UjhBG76j/DwnjrqwO',
        '管理员', 'admin', 1)
ON DUPLICATE KEY UPDATE `role` = 'admin';

-- 演示文章（tars-cms 项目自己的文档，非湖南数据）
-- 幂等：同一租户下同标题文章已存在则跳过
-- category_id 按分类名动态解析，不硬编码 id（跨环境安全）
INSERT INTO `cms_article`
    (`tenant_id`, `title`, `summary`, `category_id`, `is_banner`, `is_top`, `is_focus`, `sort`, `type`, `view_count`, `status`, `publish_at`, `cover`)
SELECT s.tenant_id, s.title, s.summary,
       (SELECT c.`id` FROM `cms_category` c
         WHERE c.`tenant_id` = s.tenant_id AND c.`name` = s.cat_name LIMIT 1) AS category_id,
       s.is_banner, s.is_top, s.is_focus, s.sort, s.type, 0, 1, NOW(), s.cover
FROM (
    SELECT 1 AS tenant_id, 'tars-cms 是什么' AS title,
           '一个写给新手的大厂微服务实战项目，用 TARS 从零搭一个能跑的内容管理系统——源自 Project-Nerv 项目拆出的 CMS 模块。' AS summary,
           '快速开始' AS cat_name, 1 AS is_banner, 1 AS is_top, 1 AS is_focus, 10 AS sort, 'doc' AS type, '/uploads/banners/banner-1-intro.jpg' AS cover
    UNION ALL SELECT 1, 'TARS 核心概念速览', 'App / Server / Servant 三层命名模型，理解 TARS 服务治理的起点。', '核心概念', 1, 1, 1, 20, 'doc', '/uploads/banners/banner-3-concept.jpg'
    UNION ALL SELECT 1, '一键部署：零干预交付', 'one-click.sh 一条命令，从干净机到生产环境全程自动：建库、服务编排、网关路由、前端发布，全链路验证 17/17。', '部署运维', 1, 1, 1, 15, 'tutorial', '/uploads/banners/banner-2-oneclick.jpg'
    UNION ALL SELECT 1, '用 tars_go 写第一个微服务', '从 IDL 定义到 tars2go 生成代码，再到 tars.Run() 跑起来，完整走一遍。', '实战教程', 1, 1, 0, 30, 'tutorial', '/uploads/banners/banner-4-go.jpg'
    UNION ALL SELECT 1, 'Docker 部署 TARS 框架', 'MySQL + framework + node 三个容器，10 分钟搭好一套 TARS 平台。', '部署运维', 1, 0, 1, 40, 'tutorial', '/uploads/banners/banner-5-docker.jpg'
    UNION ALL SELECT 1, 'TarsBenchmark 压测上手', '亲手测量你的服务 QPS 与延迟分位，验证微服务的真实性能。', '部署运维', 1, 0, 1, 50, 'tutorial', '/uploads/banners/banner-6-benchmark.jpg'
    UNION ALL SELECT 1, 'TARS 心跳与存活探测机制', '为什么服务会被反复重启？tarsnode 到底怎么判断服务活着。', '部署运维', 0, 0, 0, 60, 'doc', NULL
    UNION ALL SELECT 1, '多语言服务如何互调', '同一个 IDL，Go / Java / C++ / Node.js 各生成一份代码，透明通信。', '核心概念', 0, 0, 0, 70, 'doc', NULL
    UNION ALL SELECT 1, '网关 HTTP 与 TARS RPC 协议转换', 'TarsGateway 如何把浏览器请求转成 TARS RPC 调用。', '核心概念', 0, 0, 0, 80, 'doc', NULL
    UNION ALL SELECT 1, '开源协议选择说明', '本项目采用 GNU GPL v3.0，为什么这样选，对使用者意味着什么。', '关于项目', 0, 0, 0, 90, 'doc', NULL
    UNION ALL SELECT 1, '项目路线图与参与方式', '已完成什么、在做什么、欢迎怎么参与。', '关于项目', 0, 0, 0, 100, 'doc', NULL
) AS s
WHERE NOT EXISTS (
    SELECT 1 FROM `cms_article` a
    WHERE a.`tenant_id` = s.tenant_id AND a.`title` = s.title
);

-- 演示正文（与上面文章对应，按 title 关联）
INSERT INTO `cms_article_body` (`article_id`, `tenant_id`, `body`)
SELECT a.`id`, a.`tenant_id`, CONCAT(
    '<h2>', a.`title`, '</h2>',
    '<p>', a.`summary`, '</p>',
    '<p>本文是 tars-cms 项目的示例内容，由 CMS 自身管理。把仓库跑起来后，可以在后台管理界面里编辑、新增、删除这些文章。</p>',
    '<h3>你会在这里学到</h3>',
    '<ul><li>TARS 服务如何注册到平台</li><li>IDL 如何定义与生成代码</li><li>服务如何打包、发布、扩容</li></ul>',
    '<p>更多内容请查看仓库 <code>docs/</code> 目录。</p>'
)
FROM `cms_article` a
WHERE NOT EXISTS (SELECT 1 FROM `cms_article_body` b WHERE b.`article_id` = a.`id`);

-- 完成
SELECT '✅ tars-cms 数据库初始化完成' AS result;
SELECT
    (SELECT COUNT(*) FROM cms_category) AS categories,
    (SELECT COUNT(*) FROM cms_article)  AS articles,
    (SELECT COUNT(*) FROM users)        AS users,
    (SELECT COUNT(*) FROM cms_config)   AS configs;

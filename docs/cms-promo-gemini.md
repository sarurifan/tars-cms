# tars-cms 宣传图生成方案（Gemini 出图用）

> 使用方式：把下方任一「生成提示词（Prompt）」整段复制给 Gemini，让它生图。
> 文字处理：所有中文文案由 AI 生成时**可能出错**，两条路任选——
> ① 让 Gemini 直接生成图内文字（Gemini 中文支持较好，可接受）；
> ② 生成时提示词里写 `no text`，中文后期用 PS/稿定叠加（最稳）。
> 本文每一方案都标了中文文案的**排版位置**，方便后期叠加。

---

## 通用参数（每张图适用）

| 参数 | 值 |
|---|---|
| 画幅 | 竖版 1080×1350（4:5 杂志海报） |
| 品牌色 | 电光蓝 `#5778FF` |
| 图内英文 | `tars-cms` / `TARS` / `CONTENT` |
| 图内中文 | 见各方案"文字排版"区 |
| 风格基调 | 科技感 × 大牌/杂志封面 |

**品牌背景（写进 Prompt 前可让 Gemini 了解）**
> tars-cms 是一个用腾讯 TARS 微服务框架从零搭建的、真正能跑的内容管理系统，面向想学大厂微服务架构的新手。技术栈：TARS（Linux 基金会项目，腾讯 2008 年起使用，支撑百亿级调用）+ Go / C++ / Node.js 多语言混合。

---

## 方案 A — WIRED 科技杂志封面

**定位**：高端科技、大牌感 | 官网首屏 / 文章头图

```
Futuristic technology magazine cover, dark deep-space black background,
a large 3D wireframe content cube made of glowing electric-blue (#5778FF)
grid lines floating at center, modular node structure, small luminous data
particles and light streaks orbiting around it, subtle holographic gradient
in silver-blue-violet, volumetric light rays radiating outward, minimal clean
composition with generous empty space at the top and bottom for masthead and
headline text, editorial layout inspired by WIRED magazine covers, cinematic
studio lighting, high contrast, sharp details, premium print finish,
no text, 4:5 vertical poster
```

**文字排版（后期叠加）**
```
┌──────────────────────────┐
│ TARS REVIEW        2026  │  ← 页眉（浅灰小字）
│──────────────────────────│
│                          │
│     (3D 发光内容立方体)    │  ← 中央视觉主体 55%
│                          │
│ ━━━━━━━━━━━━━━━━━━━━━━  │
│ tars-cms                 │  ← 主标题 60pt 黑体 左对齐
│ 一个写给新手的             │
│ 「大厂微服务」实战项目      │  ← 一句话 16pt
│──────────────────────────│
│ 用 TARS 从零搭一个真正     │
│ 能跑的内容管理系统         │  ← 副文案 11pt 灰
│ 腾讯 TARS · Linux 基金会  │  ← 页脚 8pt
└──────────────────────────┘
```

---

## 方案 B — Apple Keynote 极简

**定位**：极致克制、高级 | 社媒 / 落地页

```
Minimalist keynote-style hero image, pure black background, one giant 3D
letterform "TARS-CMS" centered, letters crafted from mirror-polished chrome
with electric-blue (#5778FF) neon glow edges, subtle reflection on glossy
floor, a single thin flowing light line of data particles crossing
horizontally below the title, Apple product launch keynote aesthetic,
extreme minimalism, generous negative space, dramatic rim lighting,
ultra clean, premium tech brand feel, studio render, high-end 3D typography,
4:5 vertical poster
```

**文字排版（后期叠加）**
```
┌──────────────────────────┐
│                          │
│       T A R S            │  ← 巨型 3D 字母（图内）80% 宽
│       C M S              │
│  ────────────────        │  ← 光带横穿
│                          │
│ ─────────────────────    │
│ 一个写给新手的            │  ← 中文副标 20pt 居中
│ 「大厂微服务」实战项目     │
│ 用 TARS 从零搭一个真正    │  ← 说明 12pt 灰
│ 能跑的内容管理系统        │
│              tars-cms.dev│  ← 角标 8pt
└──────────────────────────┘
```

---

## 方案 C — Bloomberg 撞色波普

**定位**：年轻、冲击力 | 展板 / 大会物料

```
Bold geometric editorial poster in the style of Bloomberg Businessweek
covers, vibrant color blocking with electric blue (#5778FF), vivid orange
and deep purple, large abstract geometric shapes slicing the composition,
a clean white 3D modular content block at center connected by flowing data
lines and dots, halftone print texture, flat vector aesthetic mixed with
subtle 3D depth, energetic modern layout, strong diagonal composition,
premium graphic design, 4:5 vertical poster
```

**文字排版（后期叠加）**
```
┌──────────────────────────┐
│ ▓BLUE▓░ORANGE▓░PURPLE░░░│  ← 顶部色块条
│   ┌──────────────────┐  │
│   │ 白色模块卡片      │  │  ← 中央白色主体
│   └──────────────────┘  │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │
│ ▓ 一个写给新手的         ▓│  ← 底部深色块内
│ ▓ 「大厂微服务」实战项目  ▓│     白字
│ ▓ tars-cms · 内容管理系统▓│
│ ▓ 腾讯 TARS 驱动 · 百亿  ▓│
│ ▓ 级调用承载能力         ▓│
└──────────────────────────┘
```

---

## 方案 D — 赛博朋克电影海报

**定位**：科幻叙事、发布会 | 活动海报 / 预热

```
Cinematic cyberpunk movie poster, futuristic rainy city night, neon
purple-blue-orange lights reflecting on wet streets, a large glowing
holographic sphere of data and content floating above the city at center,
wireframe globe with streams of light data (#5778FF accents), volumetric
fog, film grain, anamorphic lens flare, Blade Runner inspired atmosphere,
dramatic cinematic lighting, teal and orange color grade, epic scale,
high production value movie poster composition, 4:5 vertical poster
```

**文字排版（后期叠加）**
```
┌──────────────────────────┐
│  霓虹城市夜景 + 雨丝       │
│    ┌──────────┐          │
│    │ 全息数据球│          │  ← 悬浮全息球 50%
│    └──────────┘          │
│       ‧  ‧  ‧            │
│ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁  │  ← 底部压暗遮罩
│ T A R S - C M S          │  ← 主标 宽字距 霓虹渐变
│ ─────────────────        │
│ 一个写给新手的            │  ← 14pt 白
│ 「大厂微服务」实战项目     │
│ 用 TARS 从零搭一个真正     │  ← 10pt 灰
│ 能跑的内容管理系统         │
│ 2026 · GO/C++/NODE.JS    │  ← 海报下缘 字距拉开
└──────────────────────────┘
```

---

## 方案 E — 时尚杂志极简（玻璃拟态）

**定位**：干净、高级、精致 | 品牌形象 / 高端宣传

```
High-end fashion magazine aesthetic, soft cream-to-pale-blue gradient
background, a floating translucent glass 3D cube at center, internal
refraction and caustic light effects (#5778FF tint), gentle soft shadows,
subtle light gradients, airy and clean composition, generous negative
space at top for thin elegant typography, minimal luxury style inspired
by Kinfolk and Aesop branding, frosted glass material, soft studio
lighting, premium product render, calm and sophisticated, 4:5 vertical
poster
```

**文字排版（后期叠加）**
```
┌──────────────────────────┐
│ T A R S          · 2 0 2 6│  ← 顶部字距小字 右上
│        ┌─────┐           │
│        │玻璃 │           │  ← 玻璃拟态立方体
│        │立方 │           │
│        └─────┘           │
│ ──                        │  ← 细引导线
│ tars-cms                  │  ← 主标 左对齐
│ 一个写给新手的             │
│ 「大厂微服务」实战项目      │
│ A real CMS on Tencent    │  ← 英文副标 衬线体
│ TARS                     │
│ 内容·分类·媒体·站点配置    │  ← 功能关键词 小字
│ www.tars-cms.dev         │
└──────────────────────────┘
```

---

## 方案 F — 未来数据流 Keynote

**定位**：科技峰会、知识汇聚 | 背景板 / 视频封面

```
Abstract futuristic 3D render poster, dark navy background, thousands of
luminous particles flowing like a river forming an abstract neural network
and knowledge constellation shape at center, glowing electric blue (#5778FF)
and cyan light trails, depth of field, bokeh, central bright focal point,
volumetric glow, premium octane render, tech conference keynote visual
style, elegant and futuristic, high resolution, 4:5 vertical poster
```

**文字排版（后期叠加）**
```
┌──────────────────────────┐
│      ✦  ·  ✦            │
│    ·    ╲  ╱    ·        │  ← 粒子数据流
│   · ──── ✦ ──── ·       │     汇聚成网络
│      ✦  ·  ✦            │
│ ═══════════════════════  │  ← 渐变光带
│ tars-cms                 │  ← 主标 渐变填色
│ 一个写给新手的            │
│ 「大厂微服务」实战项目     │
│ 汇聚知识，驱动创作        │  ← slogan 12pt 灰
│ TARS · GO · C++ · NODE  │  ← 页脚左
└──────────────────────────┘
```

---

# 一键安装 文案设计（配套宣传）

> 以下是「一键安装」功能的文案方向，可单独做成一张功能宣传图（方案 B 极简风格最合适），或作为主图的角标/副文案。

## 卖点提炼（来自项目实际能力）

- **一条命令装完**：`bash deploy/deploy.sh` 一键编排 n01~n11
- **幂等可重跑**：重复执行安全，改坏随时能退回去
- **断点续跑**：中断后重跑从失败处继续
- **单步可逆**：每个部署步骤独立脚本，配套回滚
- **自带测试**：9 层测试套件，30+ 断言，跑完即知全链路健康

## 文案方案

### 方案 ① 极简大字报（推荐）
```
（大标题）
一条命令，跑通一套大厂微服务

（副标题）
bash deploy/deploy.sh

（小字说明）
从数据库到网关到业务服务，一键编排 · 幂等可重跑 · 断点续跑 · 单步可回滚

（底部）
tars-cms · 用 TARS 从零搭一个真正能跑的内容管理系统
```

### 方案 ② 代码窗口
```
（模拟终端窗口，可让 AI 生成）
$ bash deploy/deploy.sh
✔ n01 初始化数据库      [OK]
✔ n02 编译打包 CmsServer [OK]
✔ n03 部署到 tarsnode   [OK]
✔ n05 网关路由注册      [OK]
✔ n09 部署 BFF          [OK]
✔ n11 全栈测试 30+ 断言  [PASS]
🎉 部署完成！

（图底文案）
一键部署 · 幂等安全 · 断点续跑 · 可回滚
```

### 方案 ③ 对比式（Before/After）
```
（左）没有 tars-cms
 多语言环境配置 · 服务注册 · 网关路由 · 心跳保活 · 部署脚本...
 手动一步步来，3 天

（右）有了 tars-cms
 bash deploy/deploy.sh
 一条命令，3 分钟

（底部）
把踩过的坑，变成一条命令
```

## 一键安装 图生成 Prompt

```
Minimalist terminal-window illustration, dark background with electric blue
(#5778FF) accents, a clean monospace command prompt showing installation
progress lines with checkmarks, modern developer tool aesthetic, floating
terminal window with subtle glow, small success indicator at the end,
flat design with soft gradients, centered composition with space around
for headline text, premium tech product feel, 4:5 vertical poster
```

**后期叠加文案**（用上面方案①或②的内容）。

---

## 选择建议

| 想表达 | 选 |
|---|---|
| 高端科技大牌感 | A / B |
| 年轻冲击力 | C / D |
| 精致干净高级 | E / F |
| 一键安装（配套） | 极简方案① + 终端窗口 Prompt |

## 出图流程

1. 先跑 A、B、F + 一键安装 四张（风格覆盖最全）
2. 满意再换 `noise_seed` / 微调 Prompt 抽变体
3. 中文文案按各方案「文字排版」区叠加（或用 Gemini 直接生成图内文字）
4. 需要品牌 LOGO / slogan 变体再回来找我

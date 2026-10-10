# tars-cms 文章图片需求与生成指南（Gemini 出图用）

> 本文档整理自 `deploy/sql/init.sql`（数据库真实文章种子）与 `h5/src/components/`（前端真实尺寸规范）。
> 用途：逐篇丢给 Gemini 生成对应的封面图与轮播图，出图后填入后台文章的「封面」字段即可。

---

## 📐 前端图片尺寸标准

根据 `h5/` 前端代码实测规范，全站仅有 **两类图片规格**：

| 规格名称 | 适用位置 | 前端 CSS 尺寸 | 推荐生成分辨率 | 比例 | 说明 |
|---|---|---|---|---|---|
| **轮播横幅（Banner）** | 首页顶部轮播图 | 容器宽 100%（max 1100px）× 高 320px | **1200 × 400** 或 **1920 × 640** | **3:1** 或 **16:9**（居中裁切） | 暗色底、右/下留白防标题遮挡 |
| **文章卡片封面（Cover）** | 首页置顶/焦点/最新网格、分类列表页 | 网格自适应（宽 280~360px）× 高 160px | **800 × 450** 或 **1200 × 675** | **16:9** | 纯视觉、主体居中、无文字 |

### 统一设计规范
- **主色调**：项目主色电光蓝 `#5778FF`，搭配深空黑/暗夜蓝（`#1a1d21` ~ `#0a0e17`）
- **文字规则**：**禁止在图内生成长中文**，AI 必翻车；仅允许少量英文科技词（`TARS` / `RPC` / `Go` / `Docker`）或**纯视觉无文字（No Text）**
- **统一风格**：现代暗色科技风、3D 概念渲染（Octane / Cinema4D 质感）、发光几何体与微服务节点连线

---

## 📑 10 篇真实文章图片需求清单

种子数据包含 10 篇文章，按前台展示权重分为 **高优先级（轮播+置顶，5篇）** 与 **普通优先级（列表卡片，5篇）**。

---

### 第一梯队：首页轮播 + 置顶（高优先级，需 16:9 封面 + 横版 Banner）

#### 01. tars-cms 是什么
- **分类**：快速开始（`getting-started`）
- **类型**：文档（`doc`）｜ **标记**：轮播图 ⭐ / 置顶 📌 / 焦点 🎯
- **当前摘要**：一个写给新手的大厂微服务实战项目，用 TARS 从零搭一个能跑的内容管理系统。
- **视觉概念**：一个由发光网格构成的现代化 3D 网站/CMS 仪表盘悬浮在深空，周边环绕微服务数据节点与代码光斑，象征"从零搭建的完整系统"。
- **图内可带英文字**：`tars-cms` / `CMS`
- **Gemini Prompt (16:9 封面 / Banner)**：
```
Modern tech editorial illustration, dark navy background (#0a0e17), a glowing 3D modular CMS dashboard interface floating at center, holographic blue (#5778FF) grid lines, floating content blocks and data cards, interconnected microservice nodes with subtle light beams, minimalist futuristic UI concept, Octane 3D render, cinematic soft lighting, clean composition with negative space, 16:9 landscape, no text
```

---

#### 02. TARS 核心概念速览
- **分类**：核心概念（`concepts`）
- **类型**：文档（`doc`）｜ **标记**：轮播图 ⭐ / 置顶 📌 / 焦点 🎯
- **当前摘要**：App / Server / Servant 三层命名模型，理解 TARS 服务治理的起点。
- **视觉概念**：清晰的三层金字塔/分层透视结构（App 顶层 → Server 中层 → Servant 底层服务节点），各层之间有半透明发光连接通道。
- **图内可带英文字**：`App` / `Server` / `Servant` / `TARS`
- **Gemini Prompt (16:9 封面 / Banner)**：
```
Futuristic 3D architecture diagram, dark background, three distinct glowing layered tiers floating vertically representing App, Server, and Servant hierarchy, interconnected by translucent electric-blue (#5778FF) light pillars, minimalist isometric perspective, clean geometric glass slabs, soft neon glow, high-end enterprise software architecture visual, 16:9 landscape, no text
```

---

#### 03. 用 tars_go 写第一个微服务
- **分类**：实战教程（`tutorials`）
- **类型**：教程（`tutorial`）｜ **标记**：轮播图 ⭐ / 置顶 📌
- **当前摘要**：从 IDL 定义到 tars2go 生成代码，再到 tars.Run() 跑起来，完整走一遍。
- **视觉概念**：Go 语言元素与微服务引擎结合，齿轮/代码芯片正在组装启动，散发强烈的"跑起来"动感与工程质感。
- **图内可带英文字**：`Go` / `tars_go` / `RPC`
- **Gemini Prompt (16:9 封面 / Banner)**：
```
Futuristic developer workspace aesthetic, dark background, a glowing cyan and electric-blue (#5778FF) microservice core being assembled, stylized glowing code glyphs transforming into 3D structural modules, Gopher-inspired blue lighting accents, high-performance backend engineering feel, sharp focus, octane render, modern tech banner, 16:9 landscape, no text
```

---

#### 04. Docker 部署 TARS 框架
- **分类**：部署运维（`deploy`）
- **类型**：教程（`tutorial`）｜ **标记**：轮播图 ⭐ / 焦点 🎯
- **当前摘要**：MySQL + framework + node 三个容器，10 分钟搭好一套 TARS 平台。
- **视觉概念**：三个发光的模块化半透明立方体容器（代表 MySQL、Framework、Node），整齐排列在虚拟主板基座上，管道与光流在它们之间穿梭互联。
- **图内可带英文字**：`Docker` / `Containers` / `TARS`
- **Gemini Prompt (16:9 封面 / Banner)**：
```
Futuristic 3D container orchestration visual, pure dark background, three glowing translucent glass container blocks aligned in a clean row, neon blue (#5778FF) and teal data pipelines flowing between them, floating above a dark metallic grid floor, subtle Docker-inspired aesthetic without logos, modern DevOps and infrastructure concept, 16:9 landscape, no text
```

---

#### 05. TarsBenchmark 压测上手
- **分类**：部署运维（`deploy`）
- **类型**：教程（`tutorial`）｜ **标记**：轮播图 ⭐ / 焦点 🎯
- **当前摘要**：亲手测量你的服务 QPS 与延迟分位，验证微服务的真实性能。
- **视觉概念**：极速流动的数据光束、仪表盘曲线、脉冲波形与高并发压力粒子流，代表极限 QPS 与百亿级吞吐。
- **图内可带英文字**：`QPS` / `Benchmark` / `Performance`
- **Gemini Prompt (16:9 封面 / Banner)**：
```
High-performance computing and benchmark concept, dark background, dramatic high-speed data streams and light trails rushing forward, floating futuristic speedometer and performance waveform holograms in neon blue and white, dynamic particle acceleration, sense of extreme throughput and low latency, cinematic studio lighting, 16:9 landscape, no text
```

---

### 第二梯队：常规文章卡片封面（仅需 16:9 卡片封面）

#### 06. TARS 心跳与存活探测机制
- **分类**：部署运维（`deploy`）
- **类型**：文档（`doc`）｜ **标记**：常规卡片
- **当前摘要**：为什么服务会被反复重启？tarsnode 到底怎么判断服务活着。
- **视觉概念**：发光的心跳脉冲曲线（ECG / 存活波形）环绕着一个服务器节点，节点持续向外扩散雷达般的检测光环。
- **图内可带英文字**：`KeepAlive` / `Probe` / `Ping`
- **Gemini Prompt (16:9 卡片封面)**：
```
Abstract cybersecurity and system health concept, dark background, a glowing server node surrounded by an electric-blue (#5778FF) pulsing radar sweep and rhythmic heartbeat lifeline wave, sentinel monitoring aesthetic, minimalist 3D composition, volumetric glow, high precision technical look, 16:9 landscape, no text
```

---

#### 07. 多语言服务如何互调
- **分类**：核心概念（`concepts`）
- **类型**：文档（`doc`）｜ **标记**：常规卡片
- **当前摘要**：同一个 IDL，Go / Java / C++ / Node.js 各生成一份代码，透明通信。
- **视觉概念**：中心是一个多边形发光多面体（代表共享 IDL 契约），向四周辐射出不同颜色/质感的光柱与节点，代表不同编程语言的互通互联。
- **图内可带英文字**：`Polyglot` / `IDL` / `RPC`
- **Gemini Prompt (16:9 卡片封面)**：
```
Abstract polyglot microservice communication concept, dark background, a central luminous crystal prism radiating four harmonized light beams in electric-blue (#5778FF), cyan, purple and amber to four surrounding floating service nodes, seamless protocol bridge concept, elegant minimalist 3D render, balanced symmetrical composition, 16:9 landscape, no text
```

---

#### 08. 网关 HTTP 与 TARS RPC 协议转换
- **分类**：核心概念（`concepts`）
- **类型**：文档（`doc`）｜ **标记**：常规卡片
- **当前摘要**：TarsGateway 如何把浏览器请求转成 TARS RPC 调用。
- **视觉概念**：桥梁或光子折射棱镜——左侧是常规的松散 Web 请求光波（HTTP），穿过中央科技网关棱镜后，转换为右侧紧密有序的高性能激光束（二进制 RPC）。
- **图内可带英文字**：`Gateway` / `HTTP ⇄ RPC`
- **Gemini Prompt (16:9 卡片封面)**：
```
Conceptual protocol gateway transformation, dark minimalist background, a sleek vertical glowing glass prism at center acting as a gateway filter, soft incoming web waves on the left transforming into sharp focused high-speed binary laser beams on the right (#5778FF), clean protocol translation concept, subtle depth of field, 16:9 landscape, no text
```

---

#### 09. 开源协议选择说明
- **分类**：关于项目（`about`）
- **类型**：文档（`doc`）｜ **标记**：常规卡片
- **当前摘要**：本项目采用 GNU GPL v3.0，为什么这样选，对使用者意味着什么。
- **视觉概念**：极简几何盾牌与开放锁扣的融合体，材质为哑光白与半透明磨砂玻璃，散发蓝白微光，象征保护与自由共享。
- **图内可带英文字**：`GPL v3.0` / `Open Source`
- **Gemini Prompt (16:9 卡片封面)**：
```
Minimalist open source software license visual, dark background, a clean geometric open-shield motif made of frosted glass and electric-blue edge lighting, symbols of digital freedom and shared community, calm authoritative tech design, premium brand mark feel, centered composition, 16:9 landscape, no text
```

---

#### 10. 项目路线图与参与方式
- **分类**：关于项目（`about`）
- **类型**：文档（`doc`）｜ **标记**：常规卡片
- **当前摘要**：已完成什么、在做什么、欢迎怎么参与。
- **视觉概念**：一条向前延伸的发光时空路径/阶段里程碑光带，节点上有发光标记，指向明亮的未来地平线。
- **图内可带英文字**：`Roadmap` / `Milestone` / `Future`
- **Gemini Prompt (16:9 卡片封面)**：
```
Futuristic product roadmap concept, dark cinematic background, an elegant glowing pathway of light leading toward a bright horizon, marked with glowing geometric milestone stepping stones in electric blue (#5778FF) and white, inspiring collaborative journey aesthetic, wide perspective, clean 3D render, 16:9 landscape, no text
```

---

## 🚀 批量生成与导入建议工作流

1. **分批生成**：
   - 第一轮：生成 01~05（这 5 篇在首页最醒目，是门面）
   - 第二轮：生成 06~10（常规列表卡片）
2. **下载落盘**：
   - 建议在本地或服务器保存为：`cover-01.jpg` ~ `cover-10.jpg`
3. **上传到 CMS**：
   - 方式 A：登录管理后台 `http://<IP>:8200/admin/` → 文章管理 → 编辑对应文章 → 在「封面」输入框填入上传后的图片 URL（可先通过素材/媒体库上传）
   - 方式 B：将图片放入 `/www/server/nginx/html/uploads/` 或通过后台上传接口，直接更新数据库 `UPDATE cms_article SET cover='...' WHERE id=X;`

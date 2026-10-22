<div align="center">
  <img src="Sources/OneRead/AppIcon.png" width="96" alt="一读 One Read 图标">
  <h1>一读 · One Read</h1>
  <p>读懂一篇外刊，积累一个新词。</p>
  <p>为 macOS 设计的英文阅读器 · 双语对照 · 划词学习 · 长难句解析</p>
  <p>
    <img src="https://img.shields.io/badge/macOS-14%2B-333333?logo=apple&amp;logoColor=white" alt="macOS 14 及以上">
    <img src="https://img.shields.io/badge/Apple_Silicon-arm64-456F56" alt="Apple Silicon arm64">
    <a href="https://github.com/Yahoo-npu/OneRead/releases"><img src="https://img.shields.io/badge/version-1.0.0-456F56" alt="版本 1.0.0"></a>
    <img src="https://img.shields.io/badge/Built_with-Swift-F05138?logo=swift&amp;logoColor=white" alt="使用 Swift 构建">
  </p>
  <p><a href="#下载与安装">下载与安装</a> · <a href="#快速开始">快速开始</a> · <a href="docs/USER_GUIDE.md">完整使用指南</a> · <a href="docs/GITHUB_PUBLISHING.md">上传与发布教程</a></p>
</div>

<p align="center">
  <img src="docs/assets/reading-journey.svg" width="960" alt="阅读旅程：导入读物、双语阅读、积累生词。示意图，并非应用截图。">
</p>

<p align="center"><sub>从一篇文章开始，把每一次阅读变成积累。</sub></p>

<a id="下载与安装"></a>

## 📥 下载与安装

<!-- RELEASE_LINKS_START -->
**[下载 macOS Apple Silicon 版](https://github.com/Yahoo-npu/OneRead/releases/download/v1.0.0/OneRead-v1.0.0-macos-arm64.zip)** · [全部版本与更新](https://github.com/Yahoo-npu/OneRead/releases) · [校验文件](https://github.com/Yahoo-npu/OneRead/releases/download/v1.0.0/SHA256SUMS.txt)

> 首次发布准备中：维护者上传 v1.0.0 安装包后，以上直接下载链接才会生效。GitHub 的“Code → Download ZIP”下载的是源码，不是安装包。
<!-- RELEASE_LINKS_END -->

当前准备发布的版本为 **1.0.0**，支持 **macOS 14 或更新版本、Apple Silicon（M 系列芯片）**。

1. 从 Releases 下载 `OneRead-v1.0.0-macos-arm64.zip`，不要下载页面自动生成的 `Source code` 源码包。
2. 解压，将“一读·One Read.app”拖入“应用程序”目录后打开。
3. 当前开发构建使用临时签名，尚未公证。如果 macOS 阻止首次打开，请核对下载来源后，到“系统设置 → 隐私与安全性”查看系统提供的打开选项；不要全局关闭系统安全保护。
4. 升级前先退出旧版本，再替换应用。书库独立保存，不放在应用包内。

Intel Mac 用户可参考 [本地构建](docs/DEVELOPMENT.md)；当前提供的安装 ZIP 不适用于 Intel，也不是 Universal 通用版本。

## ✨ 主要功能

| 功能 | 你可以做什么 |
| --- | --- |
| 📖 PDF / EPUB 阅读 | 导入无 DRM 读物，显示原文图片、封面与章节目录；点击图片放大 |
| ↔️ 双语对照 | 切换仅原文、原文译文、仅译文；联动滚动、句子悬停对应、调整两栏宽度及交换左右顺序 |
| 🌐 章节与全文翻译 | 只翻译当前章节或整本读物；停止后可继续未完成部分 |
| 🔎 划词词典 | 查看单词原形、美式音标、词性、文中释义、解释和常见释义，点击图标朗读 |
| 🧩 长难句解析 | 鼠标停留在句子上，按 **⌘T** 查看翻译、句子成分、从句和重点语法 |
| 📒 生词本 | 从阅读中收藏单词，查看出处和收录时间，按书籍筛选、搜索、归档与删除 |
| 🏷️ 考试标签 | 离线匹配 CET-4、CET-6、考研、IELTS、TOEFL 参考词表，使用不同颜色展示 |
| ☁️ 墨墨同步 | 将本地生词追加至墨墨云词本，保留云端已有词条 |
| 📰 四刊导入 | 浏览经济学人、纽约客、The Atlantic、Wired 的 EPUB 期号；启动检查新刊，由你确认导入 |
| 🗂️ 书架整理 | 自定义分类，九宫格分类封面，最近阅读，手动已读标记及阅读进度，最近删除与恢复 |
| ⚙️ 个性化与数据 | 浅色、纸张、深色主题，字号与封面大小设置，可编辑本地数据路径并迁移现有数据 |
| 💬 每日一言 | 每日更换中英双语名言，支持拖动调整区域宽度和折叠，记住显示状态 |

<a id="快速开始"></a>

## 🚀 快速开始

### 1. 导入第一本书

在首页点击 **导入读物**，选择 PDF 或 EPUB；也可点击 **导入外刊**，切换刊物、选择期号并导入。项目提供 [Samples](Samples) 示例读物，便于初次体验。

点击封面开始阅读。左侧 **目录** 用于跳转章节；**已读** 标签展示你手动标记读完的文章。点击标题末尾的小圆圈切换已读状态，书架进度随之更新。

### 2. 配置翻译服务

打开右上角设置图标，选择 **翻译服务**：

- **云端 API**：选择 DeepSeek、OpenAI、Google Gemini 或通义千问，填写自己的 API Key，选择模型，点击“测试翻译连接”。接口地址由预置配置填写；其他兼容服务使用“新增自定义配置”。
- **本地 Agent**：点击“检测本地 Agent”，选择检测结果并测试连接。首次使用需先在终端完成对应 CLI 的安装和登录；自动检测不负责安装或登录。

点击 **完成** 保存。各服务商的配置独立保留。模型候选可能随服务商变化，可用“刷新可用模型”获取列表；以账户权限和连接测试结果为准。

### 3. 开始双语阅读

点击 **翻译本章**；PDF 按其目录结构显示翻译本章或翻译本页。需要翻译整本时，使用 **更多（…）→ 翻译全文**。可以停止，稍后继续未完成部分。

在正文中拖选或双击单词，查看浮窗释义；点击朗读图标听美式发音，点击 **加入生词本** 收藏。分析句子时，将鼠标停留在句子上并按 **⌘T**。

### 4. 管理与同步生词

点击 **生词本**，按来源书籍查看，搜索单词、释义或出处，归档已掌握的词。设置里的 **墨墨同步** 可填写自己的开放 API Token，之后在生词本点击 **同步墨墨**。

墨墨同步包含全部本地生词（含归档词），不受当前筛选影响。本地删除不会删除云端词条；当前为手动单向追加，不会自动下载云端词本到本机。

更多操作见 [完整使用指南](docs/USER_GUIDE.md)。

## 🔐 数据与隐私

- 默认保存位置：`~/Library/Application Support/OneRead/`。也可在 **设置 → 本地数据** 手动输入完整路径，或选文件夹后点击 **应用路径**。
- 迁移会复制书库、原文件、图片、译文和生词，成功后切换目录，保留原位置副本；不会覆盖已有目标目录。
- API Key 和墨墨 Token 保存在 **macOS 钥匙串**，不随普通书库文件复制。
- 划词会将选中的文字和必要上下文发送给你配置的翻译服务；章节和全文翻译也会发送相关文字。保存后的原文、图片和译文可离线阅读。
- 书库和模型配置留在本机；墨墨同步会发送生词拼写，外刊检查和下载会连接 GitHub。没有内置供所有用户共享的 API Key。

## 📌 使用边界

- 支持无 DRM 的可重排 EPUB；复杂排版、脚注、精细表格和固定版式可能不能完整还原。
- PDF 保留页面预览和可选择文字；扫描件没有内置 OCR，需先用其他工具识别。无书签的 PDF 按页阅读和翻译。
- 词典释义、音标和语法解析由所选模型生成，可能有误；考试标签来自社区参考词表，不代表官方完整考试大纲。
- 全文翻译按句调用，可能产生较多请求与费用，具体取决于你配置的服务。CLI Agent 也可能连接其服务商，不等于完全离线模型。
- 外刊目录来自第三方仓库，是否有新刊以仓库实际更新为准；网络超时或 GitHub 限流时保留缓存列表。当前是应用内提醒，不是后台常驻推送。
- 当前没有自动应用更新。下载新版本后手动替换应用即可。

## 🛠️ 构建与参与

```bash
bash scripts/build.sh   # 构建应用到 dist/
bash scripts/test.sh    # Swift 回归检查；安装 Node.js 后也运行阅读器脚本检查
bash scripts/package-release.sh  # 生成发布 ZIP 和 SHA-256 校验文件
```

详见 [开发指南](docs/DEVELOPMENT.md)、[发布到 GitHub](docs/GITHUB_PUBLISHING.md) 和 [更新记录](CHANGELOG.md)。

## 🤝 来源与致谢

- 阅读界面结构参考 [cynicalight/reader](https://github.com/cynicalight/reader)，本项目独立实现。
- 外刊目录来自 [hehonghui/awesome-english-ebooks](https://github.com/hehonghui/awesome-english-ebooks)。应用与源码仓库不打包这些杂志，用户应自行确认获取和使用内容的权限。
- 词表参考 KyleBing/english-vocabulary 与 skywind3000/ECDICT；许可证和版本信息见 [第三方说明](docs/THIRD_PARTY.md)。

项目自身尚未指定开源许可证；第三方资源继续遵循各自的许可证。

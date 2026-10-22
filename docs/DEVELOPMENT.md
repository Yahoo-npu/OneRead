# 开发与项目结构

[返回首页](../README.md)

## 环境

- macOS 14 或以上。
- Xcode Command Line Tools，提供 Swift 编译器、macOS SDK、`codesign`、`sips` 等工具。未安装时可运行 `xcode-select --install`。
- Python 3 用于图标导出、资源重建与提交前检查。
- Node.js 可选；安装后 `scripts/test.sh` 会运行阅读器 JavaScript 回归检查。

应用没有第三方运行时依赖，主要使用 SwiftUI、AppKit、WebKit、PDFKit、AVFoundation 和系统语言资源。构建脚本按当前主机架构生成应用；Apple Silicon 上为 arm64，Intel 上为 x86_64，不自动生成 Universal 应用。

## 构建和验证

```bash
bash scripts/build.sh
bash scripts/test.sh
python3 scripts/check-repository.py
bash scripts/package-release.sh
```

- `VERSION`：面向用户的版本号，也是安装 ZIP 名称来源。
- `ONEREAD_BUILD_NUMBER`：可选的内部构建号。
- `ONEREAD_SDK`：可选的兼容 macOS SDK 路径。
- `ONEREAD_SIGNING_IDENTITY`：可选的本机签名身份；未设置时使用 ad-hoc 临时签名。

输出 `dist/一读·One Read.app`。发布脚本会检查版本、架构、签名和测试目录覆盖字段，再用 macOS `ditto` 压缩并生成 `SHA256SUMS.txt`。它不登录 GitHub、不上传文件、不发布 Release。

`Package.swift` 提供 Swift Package 的项目和资源描述；当前推荐使用上述脚本构建，以免本机 SwiftPM 与 SDK 的版本差异影响构建。

## 目录

```text
OneRead/
├── README.md                   # 下载、功能和快速入门
├── VERSION                     # 当前版本号
├── CHANGELOG.md                # 对用户有意义的更新
├── Package.swift               # Swift Package 描述
├── Sources/OneRead/             # 应用代码和运行所需资源
│   ├── App.swift               # 入口、主窗口与工具栏
│   ├── Store.swift             # 应用状态和数据保存
│   ├── Models.swift            # 书库、配置及模型
│   ├── Importer.swift          # PDF / EPUB 导入
│   ├── Assets.swift            # 图片及资源路径处理
│   ├── ReaderView.swift        # WebKit 阅读容器
│   ├── Reader.html             # 图文阅读与浮窗界面
│   ├── ReaderScroll.js         # 对照滚动逻辑
│   ├── ShelfHomeView.swift     # 书架与分类
│   ├── ShelfOrganization.swift # 分类、阅读记录、最近删除
│   ├── DailyQuote*.swift       # 每日一言
│   ├── ForeignMagazines.swift  # 四刊更新检查
│   ├── Economist*.swift        # 共享期刊目录与导入逻辑（保留历史命名）
│   ├── SettingsView.swift      # 分栏设置
│   ├── DataLocation.swift      # 数据路径验证与迁移
│   ├── Services.swift          # 翻译与墨墨接口
│   ├── Dictionary.swift        # 划词词典和朗读
│   ├── SentenceAnalysis.swift  # 长难句解析
│   ├── WordsView.swift         # 生词本
│   ├── AppIcon.png / .icns     # 正式图标
│   └── ExamWordListNotices/    # 第三方词表声明与许可证
├── Samples/                    # 小型自制阅读示例
├── Tests/                      # Swift / JavaScript 回归检查和预览辅助程序
├── scripts/                    # 构建、测试、打包、检查脚本
└── docs/                       # 使用、开发与发布文档
```

`design/`、`.local/`、`.build/` 与 `dist/` 保留在本地并被 Git 忽略。选定的正式图标已放进 `Sources/OneRead`，构建不依赖候选设计稿。

## 独立测试数据

运行 UI 实验时，使用与正式数据分离的目录，例如：

```bash
ONEREAD_DATA_DIR="$PWD/.local/test-library" "dist/一读·One Read.app/Contents/MacOS/OneRead"
```

请勿把个人书库用于测试。`Tests/Preview.swift` 可生成独立图文示例，其目录必须尚无 `library.json`。自动测试使用临时目录与模拟翻译/网络响应，不要求真实 API Key，也不连接个人墨墨词本。

测试覆盖导入、资源边界、翻译与词典数据、生词本、云词本响应、目录与已读、书架分类、最近删除、路径迁移，以及四刊目录和提醒队列。真实服务的账户权限、GitHub 限流和网络质量需要另行验证。

## 更新资源

正式图标：更新 `Sources/OneRead/AppIcon.png` 后运行 `python3 scripts/generate-icon.py`，重新导出各尺寸 ICNS。

考试词表：`scripts/import_exam_vocabulary.py` 从预先下载的固定版本源文件提取集合，同时更新来源清单。必须保留上游许可证；不要把参考词表描述为官方完整大纲。

期刊缓存：内置 JSON 仅包含公开仓库目录元数据，不含杂志正文。运行时会向仓库检查更新。

## 贡献前

执行提交前检查和回归测试，说明修改目的、用户可见变化及验证结果。不要提交个人书库、密钥、完整外刊文件、签名证书或本机配置。

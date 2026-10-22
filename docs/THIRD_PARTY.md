# 第三方资源与设计来源

## 考试参考词表

应用只分发英文词条集合，用于离线收录判断，不打包上游释义、例句和音频。

| 资源 | 用途 | 上游许可与固定版本 |
| --- | --- | --- |
| KyleBing/english-vocabulary | CET-4、CET-6、考研、TOEFL 词条 | BSD-3-Clause；提交 `c4c6c80879ff17d7025c28fb853a4991c8e6be6a` |
| skywind3000/ECDICT | 带 `ielts` 标签的参考词条 | MIT；提交 `bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b` |

完整说明、原始来源校验值、数量和许可证保留于 [ExamWordListNotices](../Sources/OneRead/ExamWordListNotices)。这些是社区参考词表，不是官方完整最新大纲；标签不表示考试组织的认可。

## 外刊目录

目录与下载来源为 [hehonghui/awesome-english-ebooks](https://github.com/hehonghui/awesome-english-ebooks)。内置目录快照只包含日期、路径、文件大小和 Git blob 哈希，不包含外刊正文。杂志内容由用户自行从来源获取；本项目与各杂志出版方无隶属关系。

## 界面参考

阅读区布局和交互方向参考 [cynicalight/reader](https://github.com/cynicalight/reader)。本项目使用 SwiftUI、PDFKit 和 WebKit 独立实现，未复制其源码。

## 每日一言

内置短句选自培根《论读书》、爱默生《随笔集》、梭罗《瓦尔登湖》的历史作品，英文来源链接随每条名言保存，可在界面点击作者查看。中文译文为项目内配译文。

- [Bacon — Essays](https://www.gutenberg.org/files/575/575-h/575-h.htm)
- [Emerson — Essays, First Series](https://www.gutenberg.org/files/2944/2944-h/2944-h.htm)
- [Thoreau — Walden](https://www.gutenberg.org/files/205/205-h/205-h.htm)

## 图标与示例

应用图标按本项目需求由图像生成工具制作，正式版本已包含在 `Sources/OneRead/AppIcon.png` 与 `AppIcon.icns`。本地图标候选稿不参与发布构建。

`Samples/` 为项目自制的小型阅读示例，不包含第三方外刊正文。

## 项目自身许可

当前没有为项目自身添加开源许可证。上传源码到公开仓库不代替许可证选择；第三方资源的版权声明和许可证保持原样。

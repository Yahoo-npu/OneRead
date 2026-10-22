# 考试词表来源与使用范围

版本：2026-10-21.2。应用只打包英文词条，用于离线集合匹配，不包含释义、例句、音频或上游代码。原文文件 SHA-256、固定提交及去重词条数见 manifest.json。重建脚本：scripts/import_exam_vocabulary.py。

- CET-4、CET-6、考研、TOEFL：KyleBing/english-vocabulary，BSD-3-Clause。对应 `3 四级-乱序.txt`、`4 六级-乱序.txt`、`5 考研-乱序.txt`、`6 托福-乱序.txt`。https://github.com/KyleBing/english-vocabulary/tree/c4c6c80879ff17d7025c28fb853a4991c8e6be6a
- IELTS：skywind3000/ECDICT 的 `ecdict.csv` 中 `tag` 字段包含独立 `ielts` 标记的英文词条，MIT 许可。完整 CSV 已按 Git blob SHA-1 校验后提取。https://github.com/skywind3000/ECDICT/tree/bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b

这是社区整理的考试参考词表，不是官方最新版完整大纲，也不表示官方对本应用的认可。未匹配仅表示当前词表未收录，不代表考试不考。IELTS、TOEFL 标签表示所用备考词表收录情况。各考试独立匹配，不人为推断四级词一定属于六级。大小写、空白与常见撇号归一化；变形可通过词典原形或（系统语言资源可用时）macOS 英语词形还原匹配；短语只匹配完整词条，不按包含的单词打标签。

官方四六级大纲可另行查阅：https://cet.neea.edu.cn/xhtml1/folder/16113/1588-1.htm 。当前没有将社区词表宣称为对该大纲的逐词核验版本。

许可证原文随应用附带于本目录：kyle-LICENSE.txt、ecdict-LICENSE.txt。

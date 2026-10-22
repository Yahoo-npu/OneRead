# 上传到 Yahoo-npu/OneRead 并发布下载包

[返回首页](../README.md)

目标仓库：<https://github.com/Yahoo-npu/OneRead>。

源码通过 Git 上传，应用 ZIP 通过 Releases 发布。不要把 `dist/` 或整个项目文件夹拖进 GitHub 网页上传，也不要把自己的本地数据目录放进仓库。

## 一、确认 GitHub 仓库

登录你自己的 GitHub 账户，打开目标仓库。如果尚未创建，创建名为 **OneRead** 的仓库。希望其他用户无需授权即可下载时选择 Public；私有仓库仅授权用户可访问。

首次从本地上传时，最好创建空仓库，不勾选初始化 README、`.gitignore` 或许可证。本项目已准备 README 和忽略规则；项目自身许可证尚未指定，可在决定后单独添加，第三方许可证不得移除。

如果远程已经有文件或提交，先检查并合并；不要使用 `git push --force` 覆盖它们。

## 二、在项目目录打开终端

本项目已经初始化本地 Git，当前分支为 main，尚未创建首个提交。先在终端进入项目根目录（能看到 `README.md` 和 `Package.swift` 的目录）。

```bash
python3 scripts/check-repository.py
bash scripts/test.sh
bash scripts/build.sh
bash scripts/package-release.sh
```

检查全部通过后再提交。脚本不需要个人 API Key；生成的发布 ZIP 与校验文件保存在 `dist/`。

## 三、提交本地源码

如果从未设置过 Git 提交身份，先按自己的信息设置。GitHub 的隐私邮箱可在个人设置 → Emails 中查看：

```bash
git config user.name "你的显示名称"
git config user.email "你的 GitHub 提交邮箱"
```

只提交准备好的公开项目文件：

```bash
git add .gitignore .gitattributes VERSION Package.swift README.md CHANGELOG.md docs Sources Samples Tests scripts
git status --short
git diff --cached --stat
git commit -m "Prepare One Read v1.0.0 for release"
```

确认待提交列表没有 `.build/`、`dist/`、个人 `library.json`、证书或密钥。

## 四、连接仓库并推送

```bash
git remote -v
```

没有 origin 时运行：

```bash
git remote add origin https://github.com/Yahoo-npu/OneRead.git
```

已有 origin 但地址不同，确认目标后改为：

```bash
git remote set-url origin https://github.com/Yahoo-npu/OneRead.git
```

推送：

```bash
git push -u origin main
```

GitHub 认证由你在本机完成。不要把 API Key 当作 GitHub 凭据，也不要把 GitHub 令牌粘贴到聊天、源码或 README。若尚未配置 Git 认证，可以先用 GitHub Desktop 登录自己的账户，或按官方说明配置 HTTPS / SSH 认证。

如果出现 `non-fast-forward`，表示远程已有其他提交。停止推送，先拉取并解决冲突，不要强制覆盖。

## 五、创建可下载的 Release

先为这份已推送源码打标签：

```bash
git tag v1.0.0
git push origin v1.0.0
```

然后在 GitHub 网页：

1. 打开仓库 → **Releases** → **Draft a new release**。
2. 选择标签 **v1.0.0**，目标分支 main。
3. 标题填写“一读 · One Read v1.0.0”。
4. 将 [RELEASE_NOTES_v1.0.0.md](RELEASE_NOTES_v1.0.0.md) 的内容复制到发布说明。
5. 从本地 `dist/` 上传 **OneRead-v1.0.0-macos-arm64.zip** 和 **SHA256SUMS.txt**。不要上传 `.app` 文件夹；ZIP 才能保留完整应用包结构。
6. 当前为未经公证的开发版本，可标记 **Pre-release**；确认内容和附件无误后点击 **Publish release**。

README 已指向以下地址，只有附件成功发布后才能下载：

- 安装包：<https://github.com/Yahoo-npu/OneRead/releases/download/v1.0.0/OneRead-v1.0.0-macos-arm64.zip>
- 所有版本：<https://github.com/Yahoo-npu/OneRead/releases>
- 校验文件：<https://github.com/Yahoo-npu/OneRead/releases/download/v1.0.0/SHA256SUMS.txt>

发布后请实际点击一次下载按钮，解压并打开应用。确认可下载后，可删除 README 中“首次发布准备中”提示。

安装包校验方法：将 ZIP 与 `SHA256SUMS.txt` 下载到同一文件夹，在该文件夹运行：

```bash
shasum -a 256 -c SHA256SUMS.txt
```

## 六、以后发布新版本

1. 修改代码，更新 `VERSION`、`CHANGELOG.md` 与 README 的版本及下载链接。
2. 增加内部构建号；可使用 `ONEREAD_BUILD_NUMBER=30 bash scripts/build.sh`，或更新脚本默认值。
3. 运行检查、测试、构建和打包。
4. 提交、推送源码，再打对应版本标签。
5. 创建新 Release，上传新 ZIP 和新校验文件。不要复用旧 ZIP 文件名或旧版本标签。

## 官方参考

- [把本地代码上传到 GitHub](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github)
- [创建和管理 Release](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)

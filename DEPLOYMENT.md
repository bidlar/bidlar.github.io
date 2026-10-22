# NPU.TOP：使用 Zensical 发布到 GitHub Pages

流程：修改源文件 → 推送 main → GitHub Actions 安装 Zensical → 构建 site/ → GitHub Pages 发布到 https://npu.top/。

仓库：https://github.com/bidlar/bidlar.github.io

## 只需配置一次

打开 https://github.com/bidlar/bidlar.github.io/settings/pages ：

1. Build and deployment → Source 选择 GitHub Actions。
2. Custom domain 保持为 npu.top。
3. HTTPS 证书就绪后，启用 Enforce HTTPS。

本工作流直接发布构建产物，无需选择 gh-pages 分支，也无需个人访问令牌。它使用 GitHub 自动提供的 GITHUB_TOKEN 和部署身份令牌。

## 首次发布

在项目目录预览：

```powershell
cd D:\npu_top\npu
zensical serve
```

当前电脑已安装 Zensical，可直接预览。新电脑需要先安装 Python 3.13，并在配置好 Python 命令后运行 python -m pip install -r requirements.txt。

预览确认后，在终端按 Ctrl+C 结束预览，然后执行：

```powershell
git status
git add .github .gitignore requirements.txt DEPLOYMENT.md mkdocs.yml docs supabase
git diff --cached --stat
git commit -m "Deploy NPU.TOP with Zensical"
git push origin main
```

这些命令会一起提交当前文档、个人主页、互动功能和数据库脚本。提交前查看暂存列表，确认都是本次要发布的内容。site/ 和 .cache/ 已被忽略，不需要提交生成结果。

推送后打开 https://github.com/bidlar/bidlar.github.io/actions ，查看 Publish NPU.TOP。全部步骤成功后访问 https://npu.top/ 和 https://npu.top/profile/。

如果你先推送了代码、后修改 Pages 设置，可进入 Actions → Publish NPU.TOP → Run workflow，选择 main 手动重跑。

## 日常更新

```powershell
zensical build --clean --strict
git add docs mkdocs.yml
git commit -m "Update documentation"
git push origin main
```

新增其他项目文件时将相应文件也加入提交。后续发布由 Actions 完成；不再使用 mkdocs gh-deploy。

## 版本和域名

requirements.txt 固定 Zensical 0.0.71，与当前本地验证版本一致。以后升级时先本地安装并通过构建，再修改版本号并提交。

mkdocs.yml 中 site_url 为 https://npu.top/。docs/CNAME 内容为 npu.top；构建会把它复制到 site/CNAME。GitHub Pages 的 Custom domain 也需要正确设置，单靠提交 CNAME 不能替代自定义工作流的 Pages 域名设置。

本地文件系统可能忽略大小写，GitHub Actions 的 Linux 环境会区分。贡献指南统一使用 docs/support/contribute.md，收藏链接为 support/contribute/。

## 登录和评论的独立配置

部署网站不会自动修改 Supabase。

- GitHub 登录提供商、Site URL 和 Redirect URLs 仍需在 Supabase 配置。
- 若尚未启用审核，先在 Supabase 执行 supabase/moderation.sql；当前页面会读取 status 列。
- 已启用审核后，批准评论和封禁账号不需要重新部署。
- 评论作者姓名和公开个人主页需要先在 Supabase 执行 `supabase/profiles.sql`，操作与验证见 `supabase/PROFILES.md`。该脚本会回填已有 GitHub 用户的名字和头像，并自动同步后续登录更新。
- `/profile/` 仍显示当前登录账号，`/profile/?user=用户UUID` 允许访客查看对应作者的公开名字和头像。

## 失败时查看哪里

- Configure GitHub Pages 失败：检查 Source 已选择 GitHub Actions，以及仓库允许 Actions 运行。
- Build website 失败：打开该步骤日志，根据错误修复源文件。本流程开启严格模式，构建警告也会阻止发布。
- Deploy website 失败：检查 Pages 设置及 github-pages 环境的分支/审批规则。
- 网站已更新但评论加载失败：检查 Supabase 数据表和审核升级是否已执行。

官方说明：https://zensical.org/docs/publish-your-site/

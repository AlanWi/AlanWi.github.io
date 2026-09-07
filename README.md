# AlanWi.github.io

基于 Jekyll / Chirpy 的个人博客。

## 写作与预览

文章放在 `_posts/YYYY-MM-DD-文章名.md`，顶部包含 YAML 属性。所有文章默认开启目录，可用 `toc: false` 单独关闭；包含 Mermaid 图时需要 `mermaid: true` 和 `mermaid` 代码块标记。

```bash
bundle install
bundle exec jekyll serve --livereload --unpublished
```

打开 http://127.0.0.1:4000。`published: false` 的文章可在本地预览，正式站点不会发布它们。

`note skill.md` 和各级 `.obsidian/` 目录已被 Git 忽略，本地文件保留。

## 发布前检查

向 `main` 推送或创建 PR 时，GitHub Actions 会依次检查：

- 文章和草稿的 YAML 属性、代码块语言标记及围栏闭合。
- Mermaid 内容是否误标为普通代码、是否开启 `mermaid: true`。
- 生成页面中的本地图片是否存在。
- Mermaid 图能否在浏览器中实际生成 SVG。
- 使用严格 YAML 检查完成正式 Jekyll 构建。

检查失败会阻止部署，日志会指出文件、行号或图表序号。外部网站和图片的可用性不在此检查范围内。

检查构建放在 `.jekyll-check/`，包含未发布文章和未来日期文章；该目录已从正式构建中排除。部署仍只上传 `_site/`，不会发布草稿。

本地运行完整检查需要 Ruby / Bundler、Node.js 24 和 pnpm 11.19.0。首次安装检查依赖：

```bash
pnpm --dir tools install --frozen-lockfile --ignore-scripts
pnpm --dir tools exec playwright install chromium
```

之后在项目根目录运行：

```bash
bundle exec ruby tools/check_posts.rb
bundle exec jekyll build --strict_front_matter --unpublished --drafts --future -d .jekyll-check
bundle exec ruby tools/check_site.rb .jekyll-check
node tools/check_mermaid.cjs .jekyll-check/mermaid.json
JEKYLL_ENV=production bundle exec jekyll build --strict_front_matter -d _site
```

审核后将文章设为 `published: true`，提交文章和所需图片，再推送到 `main`。检查全部通过后自动部署。

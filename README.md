# 简报台

面向移动端的境外新闻时间线。香港时间显示，按媒体的原始发布时间倒序排列。侧栏支持栏目、媒体、关键词和全文筛选。站点采用公开 GitHub Pages，访问者无需账号。站内资源与简报数据均由本站提供，原文链接由阅读者自行打开。在线界面使用 Flutter Web。页面也可以另存为单个 HTML 离线文件。

## 部署

1. 在独立 GitHub 组织建一个公开仓库，将本项目推送到 `main`。避免在组织公开资料、仓库和 Git 提交中填写私人姓名、邮箱或个人账号。
2. 在仓库 **Settings → Pages → Build and deployment → Source** 选 **GitHub Actions**。如果组织限制了 Actions，在组织及仓库中允许使用本项目的 GitHub 官方 Actions。
3. 在 **Actions → Publish edition → Run workflow** 运行一次，确认部署成功。访问地址见 Pages 设置和工作流的部署记录。

后台计划在香港时间整点和半点请求官方 RSS，GitHub Actions 排队时可能延迟。网页在相同时点检查是否发布新一期，并短时重试。手动刷新每个浏览器 30 分钟一次，独立检查最新已发布快照。收到新版时保留当前列表与阅读状态，点击「查看新版」后切换。六个预设配色和自定义主色保存在当前浏览器。维护任务仅在仓库连续 28 天没有提交时写入空提交，以保留公共仓库的排程活跃度。过期条目按原文发布时间滚动清除，正文与摘要只在 Pages 当前版本及短时部署制品中存在，不写入 Git 历史；离线副本及外部缓存由其持有者管理。

## 来源与转载

仅消费 `sources.json` 中列明的媒体官方 RSS，逐条核对域名，过滤专题范围以外的条目。RSS 暂时故障时保留未过期的报道。所有标题和摘要默认显示原文。非中文条目的「翻译」按钮优先展开 Google Cloud Translation 的译文，未配置服务时会尝试 Chrome 桌面内置翻译，其他浏览器可打开 Google 翻译。简报依据媒体发布的 RSS 摘要裁剪，只有标题的源也只显示标题。

正文仅取两类满足条件的官方订阅条目：自由亚洲电台 RSS 中有明确记者署名的原稿，以及没有合作伙伴转载标记的 Global Voices 自有稿件。正文保留原语种，署名、条款和原文链接在站内标示。图像、视频、嵌入及第三方稿件均不复制。来源使用条款变更时，更新 `sources.json` 中的 `full` 授权配置，或移除来源。

## 本地构建

使用 Python 3.12 和 Flutter 3.50.1。从项目目录执行 `bash scripts/web-assets.sh`，然后在 `app/` 内执行 `flutter pub get` 和 `flutter build web --release --pwa-strategy=none --no-web-resources-cdn`。将 `app/build/web` 的内容复制到 `dist`。安装 `scripts/requirements.txt` 后运行 `python scripts/refresh.py`，用 HTTP 服务打开 `dist/`，也可以直接打开 `dist/offline.html`。已有上期数据可使用 `--previous path/to/feed.json` 合并七天内的条目。

## Google 翻译

已发布的站内译文使用 [Google Cloud Translation](https://cloud.google.com/translate)。可在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 添加 `GOOGLE_TRANSLATE_API_KEY`。需要先在 Google Cloud 项目启用 Cloud Translation API，并自行设置费用与用量限制。密钥仅传入发布工作流，不写入页面或快照。每次构建最多翻译 600 个字符，优先处理新稿件，并沿用未过期的既有谷歌译文。

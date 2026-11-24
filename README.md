# 新闻简报

面向移动端的境外新闻时间线。香港时间显示，按媒体的原始发布时间倒序排列。侧栏支持栏目、媒体、关键词和全文筛选。站点采用公开 GitHub Pages，访问者无需账号。站内资源与简报数据均由本站提供，原文链接由阅读者自行打开。在线界面使用 Flutter Web。页面也可以另存为单个 HTML 离线文件。

## 部署

1. 在独立 GitHub 组织建一个公开仓库，将本项目推送到 `main`。避免在组织公开资料、仓库和 Git 提交中填写私人姓名、邮箱或个人账号。
2. 在仓库 **Settings → Pages → Build and deployment → Source** 选 **GitHub Actions**。如果组织限制了 Actions，在组织及仓库中允许使用本项目的 GitHub 官方 Actions。
3. 在 **Actions → Publish edition → Run workflow** 运行一次，确认部署成功。访问地址见 Pages 设置和工作流的部署记录。

后台计划在香港时间整点和半点请求官方 RSS，GitHub Actions 排队时可能延迟。网页在相同时点检查是否发布新一期，并短时重试。手动刷新每个浏览器 30 分钟一次，独立检查最新已发布快照。固定顶栏显示检查时间、发布时间、新增条数和过旧状态。收到新版时保留当前列表与阅读状态，点击「查看新版」后切换。七个预设配色和自定义主色均支持独立的日间与夜间模式，保存在当前浏览器。维护任务仅在仓库连续 28 天没有提交时写入空提交，以保留公共仓库的排程活跃度。过期条目按原文发布时间滚动清除，正文与摘要只在 Pages 当前版本及短时部署制品中存在，不写入 Git 历史；离线副本及外部缓存由其持有者管理。

## 来源与转载

从 `sources.json` 列明的官方 RSS 和授权转载频道获取报道。路透社只收录 Investing.com 订阅中明确署名 Reuters 的稿件。按文章提及的地区放入已有栏目。RSS 暂时故障时保留未过期的报道。所有标题和摘要默认显示原文。英文和日文报道可在原文下方展开简体译文。支持浏览器翻译时优先使用其结果。Firefox 等浏览器可以显示发布时预生成的 Mozilla Bergamot 译文（英译中 2.2，日译英 2.1 后转译）。简体和繁体新闻均直接显示原文。日本媒体包括 NHK、朝日新闻、每日新闻、时事通信、TBS 和 FNN。简报依据媒体发布的 RSS 摘要裁剪，只有标题的源也只显示标题。

正文仅取两类满足条件的官方订阅条目：自由亚洲电台 RSS 中有明确记者署名的原稿，以及没有合作伙伴转载标记的 Global Voices 自有稿件。正文保留原语种，署名、条款和原文链接在站内标示。图像、视频、嵌入及第三方稿件均不复制。来源使用条款变更时，更新 `sources.json` 中的 `full` 授权配置，或移除来源。

## 本地构建

使用 Python 3.12、Node.js 22 和 Flutter 3.50.1。从项目目录执行 `bash scripts/web-assets.sh`，然后在 `app/` 内执行 `flutter pub get` 和 `flutter build web --release --pwa-strategy=none --no-web-resources-cdn`。将 `app/build/web` 的内容复制到 `dist`。安装 `scripts/requirements.txt` 后运行 `python scripts/refresh.py`，用 HTTP 服务打开 `dist/`，也可以直接打开 `dist/offline.html`。已有上期数据可使用 `--previous path/to/feed.json` 合并七天内的条目。

## AI 分析

每条报道均可打开右侧分析面板，默认选择 Grok。支持 Grok、ChatGPT、Gemini和 Claude。已生成的分析直接随新闻快照发布。没有生成分析时，面板显示媒体原文提要，并可复制提问或前往相应的官方服务。只处理已授权的正文或 RSS 中的标题和摘要。顶栏「AI 分析」提供香港时间今天的速览。没有模型结果时，展示按地区和来源选取的要闻。

站内自动分析可使用仓库 **Settings → Secrets and variables → Actions** 中的 `XAI_API_KEY`、`OPENAI_API_KEY`、`GEMINI_API_KEY`或 `ANTHROPIC_API_KEY`。没有配置相应密钥时，发布任务不调用该服务。每个已启用的服务在单次构建最多分析四条报道和一次今日速览。已生成的分析随对应新闻滚动保留。可通过同页变量 `NEWS_MODEL_GROK` 等覆盖模型名。

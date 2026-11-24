import 'package:flutter/material.dart';

import 'analysis_panel.dart';
import 'model.dart';
import 'platform.dart';

class ArticleCard extends StatefulWidget {
  const ArticleCard({
    super.key,
    required this.article,
    required this.publisher,
    required this.compact,
  });
  final Article article;
  final Publisher publisher;
  final bool compact;

  @override
  State<ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<ArticleCard>
    with AutomaticKeepAliveClientMixin {
  bool expanded = false;
  bool waiting = false;
  Translation? browserTranslation;
  Article get article => widget.article;
  Publisher get publisher => widget.publisher;

  @override
  bool get wantKeepAlive => expanded;

  Future<void> toggleTranslation() async {
    setState(() => expanded = !expanded);
    updateKeepAlive();
    if (expanded) await loadTranslation();
  }

  Future<void> loadTranslation() async {
    if (browserTranslation != null || waiting) return;
    setState(() => waiting = true);
    final translated = await translateInBrowser(article);
    if (!mounted) return;
    setState(() {
      waiting = false;
      browserTranslation = translated;
    });
  }

  Widget translationPanel(ColorScheme colors) {
    final translation = browserTranslation ?? article.translation;
    return Container(
      key: ValueKey(article.url),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6, bottom: 3),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .38),
        border: Border(
          left: BorderSide(
            color: colors.primary.withValues(alpha: .55),
            width: 2,
          ),
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: waiting && translation == null
          ? const Row(
              children: [
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 9),
                Text('正在翻译…'),
              ],
            )
          : translation == null
          ? TextButton.icon(
              onPressed: loadTranslation,
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('本站暂未提供译文 · 重试'),
            )
          : SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    translation.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      height: 1.48,
                    ),
                  ),
                  if (translation.summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(translation.summary),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    translation.provider,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final compact = widget.compact;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 13 : 19,
        14,
        compact ? 13 : 19,
        11,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact) ...[
            SizedBox(
              width: 54,
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  hongKongClock(article.publishedAt),
                  style: text.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.fromLTRB(0, 9, 15, 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withValues(alpha: .7),
              ),
            ),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 9,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (compact)
                      Text(
                        hongKongClock(article.publishedAt),
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    Text(
                      publisher.name,
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    ...article.topics.map(
                      (topic) => Text(
                        topic,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (article.kind == '评论')
                      Text(
                        '评论',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        style: text.titleLarge?.copyWith(
                          fontSize: compact ? 18 : 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.2,
                          height: 1.48,
                        ),
                      ),
                      if (article.summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5, bottom: 1),
                          child: Text(
                            article.summary,
                            style: text.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.66,
                              fontSize: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 5,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (article.canTranslate)
                      TextButton.icon(
                        onPressed: toggleTranslation,
                        icon: const Icon(Icons.translate, size: 15),
                        label: Text(expanded ? '收起译文' : '翻译'),
                      ),
                    if (article.full != null)
                      TextButton(
                        onPressed: () =>
                            showArticle(context, article, publisher),
                        child: const Text('站内读全文'),
                      ),
                    TextButton(
                      onPressed: () => openLink(article.url),
                      child: const Text('查看原文'),
                    ),
                    if (publisher.credit != null)
                      Text(
                        publisher.credit!,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => showAnalysis(context, article, publisher),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 14),
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    label: const Text('AI 分析'),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 230),
                    child: expanded
                        ? translationPanel(colors)
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showArticle(
  BuildContext context,
  Article article,
  Publisher publisher,
) {
  final full = article.full!;
  return showDialog<void>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: SizedBox(
          width: 700,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 9, 12, 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${publisher.name} · ${hongKongDate(article.publishedAt)}',
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭文章',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 15, 22, 26),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          full['title'] as String? ?? article.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          full['byline'] as String,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: () => openLink(article.url),
                              child: const Text('原文'),
                            ),
                            TextButton(
                              onPressed: () => openLink(
                                Uri.parse(full['license'] as String),
                              ),
                              child: Text(full['licenseLabel'] as String),
                            ),
                          ],
                        ),
                        Text(
                          full['credit'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        for (final paragraph
                            in (full['body'] as List).cast<String>())
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              paragraph,
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.85,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

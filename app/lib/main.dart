import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';

import 'model.dart';
import 'platform.dart';
import 'reader.dart';
import 'theme.dart';

void main() => runApp(const Fieldnote());

class Fieldnote extends StatefulWidget {
  const Fieldnote({super.key});

  @override
  State<Fieldnote> createState() => _FieldnoteState();
}

class _FieldnoteState extends State<Fieldnote> {
  late Palette palette = currentPalette();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '新闻简报',
      themeAnimationDuration: const Duration(milliseconds: 300),
      themeAnimationCurve: Curves.easeOutCubic,
      debugShowCheckedModeBanner: false,
      theme: fieldnoteTheme(palette),
      home: NewsDesk(
        palette: palette,
        onPalette: (value) {
          rememberPalette(value);
          setState(() => palette = value);
        },
      ),
    );
  }
}

class NewsDesk extends StatefulWidget {
  const NewsDesk({super.key, required this.palette, required this.onPalette});
  final Palette palette;
  final ValueChanged<Palette> onPalette;

  @override
  State<NewsDesk> createState() => _NewsDeskState();
}

class _NewsDeskState extends State<NewsDesk>
    with SingleTickerProviderStateMixin {
  static const refreshKey = 'fieldnote-last-manual-refresh';
  static const spacing = Duration(minutes: 30);
  static const retries = [20, 45, 90, 180, 360];

  final query = TextEditingController();
  final scroll = ScrollController();
  Edition? edition;
  Edition? pending;
  int selectedTopic = 0;
  String publisherId = '';
  bool fullOnly = false;
  String notice = '';
  DateTime? checkedAt;
  late final AnimationController spin;
  Set<Uri> currentLinks = <Uri>{};
  int pendingNewArticles = 0;
  bool busy = false;
  bool failedInitial = false;
  final Stopwatch _manualDuration = Stopwatch();
  late int manualAt = int.tryParse(readPreference(refreshKey) ?? '') ?? 0;
  int? slot;
  bool autoDeferred = false;
  int limit = 45;
  Timer? nextSlot;
  Timer? retry;
  Timer? cooldown;
  JSFunction? visibility;

  @override
  void initState() {
    super.initState();
    spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 740),
    );
    visibility = ((JSAny? _) => schedule()).toJS;
    onVisibilityChange(null, visibility);
    schedule();
    armCooldown();
  }

  @override
  void dispose() {
    for (final timer in [nextSlot, retry, cooldown]) {
      timer?.cancel();
    }
    onVisibilityChange(visibility, null);
    scroll.dispose();
    query.dispose();
    spin.dispose();
    super.dispose();
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;
  int get remaining => manualAt + spacing.inMilliseconds - _now;

  void armCooldown() {
    cooldown?.cancel();
    final wait = remaining;
    if (wait > 0) {
      cooldown = Timer(Duration(milliseconds: wait + 50), () {
        if (mounted)
          setState(() {
            if (notice.startsWith('约 ')) notice = '';
          });
      });
    }
  }

  Future<Edition> check() async {
    final result = await fetchEdition();
    if (!mounted) return result;
    setState(() {
      checkedAt = DateTime.now().toUtc();
      if (edition == null) {
        edition = result;
        currentLinks = result.items.map((item) => item.url).toSet();
        failedInitial = false;
      } else if (result.updatedAt.isAfter((pending ?? edition!).updatedAt)) {
        pending = result;
        pendingNewArticles = result.items
            .where((item) => !currentLinks.contains(item.url))
            .length;
      }
    });
    return result;
  }

  bool get staleEdition {
    final publication = (pending ?? edition)?.updatedAt;
    return publication != null &&
        DateTime.now().toUtc().difference(publication) >
            const Duration(minutes: 50);
  }

  Future<void> manualRefresh() async {
    if (busy) return;
    final saved = int.tryParse(readPreference(refreshKey) ?? '') ?? 0;
    if (saved > manualAt) manualAt = saved;
    if (remaining > 0) {
      setState(() => notice = '约 ${(remaining / 60000).ceil()} 分钟后可再次手动刷新');
      armCooldown();
      return;
    }
    manualAt = _now;
    writePreference(refreshKey, manualAt.toString());
    armCooldown();
    _manualDuration.reset();
    _manualDuration.start();
    if (!MediaQuery.disableAnimationsOf(context)) spin.repeat();
    setState(() {
      busy = true;
      notice = '正在检查新一期…';
    });
    var success = false;
    try {
      await check();
      success = true;
    } catch (_) {
      // Keep the current articles during an outage and allow a retry.
      manualAt = 0;
      writePreference(refreshKey, '0');
      armCooldown();
    } finally {
      final delay = 1050 - _manualDuration.elapsedMilliseconds;
      if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
      _manualDuration.stop();
      if (mounted) {
        spin.stop();
        spin.value = 0;
        setState(() {
          busy = false;
          failedInitial = !success && edition == null;
          notice = !success
              ? '检查失败，点刷新重试'
              : pending != null
              ? '检测到新一期'
              : staleEdition
              ? '本次无新版，发布已延迟'
              : '本次检查无新版';
        });
      }
    }
  }

  void schedule() {
    nextSlot?.cancel();
    final now = _now;
    final interval = spacing.inMilliseconds;
    final current = now ~/ interval * interval;
    if (pageIsVisible && (slot != current || autoDeferred)) {
      retry?.cancel();
      slot = current;
      autoDeferred = false;
      unawaited(autoRefresh(current));
    }
    nextSlot = Timer(
      Duration(milliseconds: current + interval - now),
      schedule,
    );
  }

  Future<void> autoRefresh(int current, [int attempt = 0]) async {
    if (!mounted || slot != current) return;
    if (!pageIsVisible) {
      autoDeferred = true;
      return;
    }
    try {
      final result = await check();
      if (result.updatedAt.millisecondsSinceEpoch >= current) return;
    } catch (_) {
      if (mounted && edition == null) setState(() => failedInitial = true);
    }
    if (!mounted || slot != current || attempt >= retries.length) return;
    final wait = current + retries[attempt] * 1000 - _now;
    retry = Timer(
      Duration(milliseconds: wait > 0 ? wait : 0),
      () => unawaited(autoRefresh(current, attempt + 1)),
    );
  }

  void showNewEdition() {
    if (pending == null) return;
    setState(() {
      edition = pending;
      currentLinks = edition!.items.map((item) => item.url).toSet();
      pending = null;
      pendingNewArticles = 0;
      if (!edition!.sources.containsKey(publisherId)) publisherId = '';
      notice = '已切换到最新一期';
    });
  }

  void changeFilters(VoidCallback change) {
    setState(() {
      change();
      limit = 45;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  List<Article> results(Edition data) {
    final words = query.text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    return data.items.where((article) {
      if (selectedTopic != 0 && !article.topics.contains(topics[selectedTopic]))
        return false;
      if (publisherId.isNotEmpty && article.publisher != publisherId)
        return false;
      if (fullOnly && article.full == null) return false;
      final content = [
        article.title,
        article.summary,
        data.sources[article.publisher]?.name ?? '',
        ...article.topics,
      ].join(' ').toLowerCase();
      return words.every(content.contains);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, layout) {
            final compact = layout.maxWidth < 790;
            return Column(
              children: [
                masthead(compact),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1190),
                      child: Row(
                        children: [
                          if (!compact) sidebar(),
                          Expanded(child: timeline(compact)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget masthead(bool compact) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: .75),
          ),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1190),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 21,
              8,
              compact ? 12 : 23,
              7,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      width: 37,
                      height: 37,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.notes_rounded,
                        size: 23,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Text(
                      '新闻简报',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .2,
                      ),
                    ),
                    const Spacer(),
                    if (!compact) ...[
                      PaletteRow(
                        selected: widget.palette,
                        onChanged: widget.onPalette,
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      tooltip: '保存离线版',
                      icon: const Icon(Icons.file_download_outlined),
                      onPressed: edition == null ? null : saveOffline,
                    ),
                    const SizedBox(width: 4),
                    refreshControl(),
                  ],
                ),
                const SizedBox(height: 4),
                publicationStatus(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget publicationStatus() {
    final colors = Theme.of(context).colorScheme;
    final publication = (pending ?? edition)?.updatedAt;
    final status = busy
        ? '正在检查新一期…'
        : pending != null
        ? '新一期已就绪'
        : notice.isNotEmpty
        ? notice
        : staleEdition
        ? '发布已延迟'
        : '整点、半点检查';
    final times = [
      if (publication != null) '发布 ${hongKongClock(publication)}',
      if (checkedAt != null) '检查 ${hongKongClock(checkedAt!)}',
    ].join(' · ');
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 210),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, if (current != null) current],
                    ),
                    child: Text(
                      status,
                      key: ValueKey(status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: staleEdition && !busy
                            ? colors.error
                            : colors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (times.isNotEmpty)
                    Text(
                      '$times · 香港时间',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: pending == null
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: showNewEdition,
                    child: Text(
                      pendingNewArticles == 0
                          ? '查看新版'
                          : '查看 ${pendingNewArticles} 条新报道',
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget refreshControl() {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: busy
          ? '正在检查新一期'
          : remaining > 0
          ? '每 30 分钟可手动检查一次'
          : '手动检查新一期',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: busy
              ? colors.primaryContainer
              : colors.secondaryContainer.withValues(alpha: .70),
        ),
        child: TextButton.icon(
          icon: RotationTransition(
            turns: spin,
            child: const Icon(Icons.refresh_rounded, size: 20),
          ),
          onPressed: busy ? null : manualRefresh,
          style: TextButton.styleFrom(
            foregroundColor: colors.onPrimaryContainer,
            disabledForegroundColor: colors.onPrimaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          ),
          label: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(busy ? '更新中' : '刷新', key: ValueKey(busy)),
          ),
        ),
      ),
    );
  }

  Widget sidebar() {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 250,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(21, 23, 20, 16),
        children: [
          Text(
            '栏目',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < topics.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Material(
                color: selectedTopic == index
                    ? colors.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => changeFilters(() => selectedTopic = index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    child: Text(
                      topics[index],
                      style: TextStyle(
                        color: selectedTopic == index
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                        fontWeight: selectedTopic == index
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 13),
          ...publisherControls(),
        ],
      ),
    );
  }

  List<Widget> publisherControls({VoidCallback? onChange}) {
    final data = edition;
    return [
      DropdownButtonFormField<String>(
        key: ValueKey(publisherId),
        isExpanded: true,
        initialValue: publisherId,
        decoration: const InputDecoration(labelText: '媒体'),
        items: [
          const DropdownMenuItem(value: '', child: Text('全部媒体')),
          if (data != null)
            ...data.sources.entries.map(
              (entry) => DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value.name),
              ),
            ),
        ],
        onChanged: data == null
            ? null
            : (value) {
                changeFilters(() => publisherId = value ?? '');
                onChange?.call();
              },
      ),
      const SizedBox(height: 9),
      CheckboxListTile(
        value: fullOnly,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('仅看可读全文', style: TextStyle(fontSize: 14)),
        onChanged: (value) {
          changeFilters(() => fullOnly = value ?? false);
          onChange?.call();
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: data == null ? null : () => showPublishers(data),
          icon: const Icon(Icons.public, size: 16),
          label: const Text('媒体与更新状态'),
        ),
      ),
    ];
  }

  void showFilters() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, sheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '筛选报道',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭筛选',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...publisherControls(
                  onChange: () {
                    if (context.mounted) sheetState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void showPublishers(Edition data) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('媒体与更新状态'),
        content: SizedBox(
          width: 500,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('香港时间整点、半点计划抓取。手动刷新检查本站最新已发布的快照。'),
              const SizedBox(height: 12),
              for (final publisher in data.sources.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(publisher.name),
                  subtitle: Text(
                    '${publisher.region} · ${publisher.health.any((feed) => feed['error'] == null) ? '订阅可用' : '订阅暂不可用'}',
                  ),
                  trailing: IconButton(
                    tooltip: '打开媒体',
                    onPressed: () => openLink(publisher.site),
                    icon: const Icon(Icons.open_in_new, size: 17),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget timeline(bool compact) {
    final colors = Theme.of(context).colorScheme;
    final data = edition;
    final articles = data == null ? const <Article>[] : results(data);
    final shown = articles.take(limit).toList();
    final grouped = <Object>[];
    String? previousDay;
    for (final article in shown) {
      final day = hongKongDate(article.publishedAt);
      if (day != previousDay) {
        grouped.add(article.publishedAt);
        previousDay = day;
      }
      grouped.add(article);
    }

    return CustomScrollView(
      controller: scroll,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            compact ? 13 : 4,
            compact ? 16 : 25,
            compact ? 13 : 23,
            25,
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(child: intro(compact, data, articles.length)),
              if (data == null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: failedInitial
                          ? TextButton(
                              onPressed: () => unawaited(
                                check().then<void>((_) {}, onError: (_) {}),
                              ),
                              child: const Text('消息暂未载入，重试'),
                            )
                          : const CircularProgressIndicator(),
                    ),
                  ),
                )
              else if (shown.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Text('没有符合筛选条件的报道。'),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: grouped.length,
                  itemBuilder: (context, index) {
                    final item = grouped[index];
                    if (item is DateTime) return dayHeading(item);
                    final article = item as Article;
                    return DecoratedBox(
                      key: ValueKey(article.url),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border(
                          left: BorderSide(color: colors.outlineVariant),
                          right: BorderSide(color: colors.outlineVariant),
                          bottom: BorderSide(color: colors.outlineVariant),
                        ),
                      ),
                      child: ArticleCard(
                        article: article,
                        publisher: data.sources[article.publisher]!,
                        compact: compact,
                      ),
                    );
                  },
                ),
              if (articles.length > limit)
                SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: OutlinedButton(
                        onPressed: () => setState(() => limit += 45),
                        child: const Text('显示更多报道'),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget dayHeading(DateTime date) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: Container(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            colors.primary.withValues(alpha: .07),
            colors.surface,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border.all(color: colors.outlineVariant),
        ),
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: colors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              hongKongDate(date),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(width: 9),
            Text(
              hongKongWeekday(date),
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget intro(bool compact, Edition? data, int count) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact) ...[
          PaletteRow(selected: widget.palette, onChanged: widget.onPalette),
          const SizedBox(height: 6),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.alphaBlend(
                  widget.palette.seed.withValues(alpha: .16),
                  colors.surface,
                ),
                colors.surface,
              ],
            ),
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.fromLTRB(
            compact ? 15 : 24,
            15,
            compact ? 15 : 24,
            16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最近七天 · 香港时间',
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, .12),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: Text(
                  topics[selectedTopic],
                  key: ValueKey(selectedTopic),
                  style: TextStyle(
                    fontSize: compact ? 32 : 43,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (compact)
          Padding(
            padding: const EdgeInsets.only(top: 11),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < topics.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        label: Text(topics[index]),
                        selected: selectedTopic == index,
                        showCheckmark: false,
                        onSelected: (_) =>
                            changeFilters(() => selectedTopic = index),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: query,
                onChanged: (_) => changeFilters(() {}),
                decoration: InputDecoration(
                  hintText: '搜索标题、摘要或媒体',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => changeFilters(query.clear),
                        ),
                  filled: true,
                  fillColor: colors.surface,
                ),
              ),
            ),
            if (compact) ...[
              const SizedBox(width: 9),
              OutlinedButton.icon(
                onPressed: showFilters,
                icon: const Icon(Icons.tune, size: 17),
                label: const Text('筛选'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 9),
        if (data != null)
          Row(
            children: [
              Text(
                '$count 条报道',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
              const Spacer(),
              Text(
                '按原文发布时间排序',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
      ],
    );
  }
}

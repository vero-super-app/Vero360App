import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/main_marketPlace.dart';
import 'package:vero360_app/features/Promotions/presentation/promotions_page.dart';
import 'package:vero360_app/features/Promotions/promotion_service.dart';
import 'package:vero360_app/Home/notifications_page.dart';
import 'package:vero360_app/utils/app_update_checker.dart';
import 'package:vero360_app/utils/app_version_info.dart';

/// Plain text crawl in the orange hero.
/// Fed by admin `homepage_crawls` plus live promotions.
/// Admin `linkType: app_update` scrolls with an Update chip when a newer version is posted.
class HomepageCrawlTicker extends StatefulWidget {
  const HomepageCrawlTicker({super.key});

  @override
  State<HomepageCrawlTicker> createState() => _HomepageCrawlTickerState();
}

class _CrawlItem {
  final String id;
  final String text;
  final String linkType;
  final String linkId;
  final String latestVersion;

  const _CrawlItem({
    required this.id,
    required this.text,
    required this.linkType,
    this.linkId = '',
    this.latestVersion = '',
  });

  bool get isAppUpdate => linkType.toLowerCase().trim() == 'app_update';

  bool get hasAction {
    final t = linkType.toLowerCase().trim();
    return t.isNotEmpty && t != 'none';
  }

  /// Short CTA on the crawl chip.
  String get actionLabel {
    switch (linkType.toLowerCase().trim()) {
      case 'app_update':
        return 'Update';
      case 'promotion':
      case 'promotions':
        return 'Promos';
      case 'marketplace':
        return 'Shop';
      case 'announcements':
        return 'More';
      default:
        return 'Open';
    }
  }

  String get versionLabel {
    final v = latestVersion.trim().isNotEmpty
        ? latestVersion.trim()
        : linkId.trim();
    return v;
  }
}

class _HomepageCrawlTickerState extends State<HomepageCrawlTicker>
    with SingleTickerProviderStateMixin {
  /// Steady news-ticker pace (readable on phone).
  static const double _pixelsPerSecond = 26;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _crawlSub;
  List<_CrawlItem> _adminItems = const [];
  List<String> _promoTitles = const [];
  late final AnimationController _controller;
  double _loopWidth = 0;

  static String _shortTitle(String text) {
    var t = text.trim();
    final lower = t.toLowerCase();
    for (final prefix in ['promos:', 'promo:', 'marketplace:', 'announcement:']) {
      if (lower.startsWith(prefix)) {
        t = t.substring(prefix.length).trim();
        break;
      }
    }
    // Drop "title — subtitle" down to title only for the list.
    final dash = t.indexOf(' — ');
    if (dash > 0) t = t.substring(0, dash).trim();
    return t;
  }

  /// One crawl line per destination (e.g. all promos together).
  List<_CrawlItem> _groupByLinkType(List<_CrawlItem> items) {
    final noneOrPlain = <_CrawlItem>[];
    final byType = <String, List<_CrawlItem>>{};

    for (final item in items) {
      final t = item.linkType.toLowerCase().trim();
      if (t.isEmpty || t == 'none') {
        noneOrPlain.add(item);
        continue;
      }
      // Promotions are merged with live promos separately.
      if (t == 'promotion' || t == 'promotions') continue;
      (byType[t] ??= []).add(item);
    }

    final grouped = <_CrawlItem>[];
    for (final entry in byType.entries) {
      final list = entry.value;
      final titles = list
          .map((i) => _shortTitle(i.text))
          .where((s) => s.isNotEmpty)
          .toList();
      if (titles.isEmpty) continue;

      final prefix = switch (entry.key) {
        'marketplace' => 'Marketplace',
        'announcements' => 'News',
        _ => null,
      };
      final text = prefix == null
          ? titles.join(', ')
          : (titles.length == 1
              ? '$prefix: ${titles.first}'
              : '$prefix: ${titles.join(', ')}');

      grouped.add(
        _CrawlItem(
          id: 'group_${entry.key}',
          text: text,
          linkType: entry.key,
        ),
      );
    }

    return [...noneOrPlain, ...grouped];
  }

  /// Crawl stream: pending app update first, then grouped admin crawls, then one promos line.
  List<_CrawlItem> get _items {
    final updates = <_CrawlItem>[];
    final others = <_CrawlItem>[];
    final adminPromoTitles = <String>[];

    for (final item in _adminItems) {
      if (item.isAppUpdate) {
        final target = item.versionLabel;
        if (target.isEmpty) continue;
        if (!AppUpdateChecker.isNewerVersion(target, AppVersionInfo.version)) {
          continue;
        }
        updates.add(
          _CrawlItem(
            id: item.id,
            text: 'Update to latest version v$target',
            linkType: item.linkType,
            linkId: item.linkId,
            latestVersion: item.latestVersion,
          ),
        );
        continue;
      }

      final t = item.linkType.toLowerCase().trim();
      if (t == 'promotion' || t == 'promotions') {
        final title = _shortTitle(item.text);
        if (title.isNotEmpty) adminPromoTitles.add(title);
        continue;
      }
      others.add(item);
    }

    final promoNames = <String>[
      ...adminPromoTitles,
      ..._promoTitles,
    ];
    // Dedupe case-insensitively, keep order.
    final seen = <String>{};
    final uniquePromos = <String>[];
    for (final name in promoNames) {
      final key = name.toLowerCase();
      if (seen.add(key)) uniquePromos.add(name);
    }

    final promoLine = uniquePromos.isEmpty
        ? null
        : _CrawlItem(
            id: 'promos_grouped',
            text: 'Promos: ${uniquePromos.take(10).join(', ')}',
            linkType: 'promotions',
          );

    return [
      ...updates,
      ..._groupByLinkType(others),
      if (promoLine != null) promoLine,
    ];
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _listenCrawls();
    _loadPromos();
  }

  void _listenCrawls() {
    _crawlSub = FirebaseFirestore.instance
        .collection('homepage_crawls')
        .snapshots()
        .listen((snap) {
      final list = snap.docs
          .map((d) {
            final data = d.data();
            if (data['active'] == false) return null;
            final title = (data['title'] ?? '').toString().trim();
            if (title.isEmpty) return null;
            final subtitle = (data['subtitle'] ?? data['body'] ?? '')
                .toString()
                .trim();
            final linkType = (data['linkType'] ?? 'none').toString();
            final latestVersion = (data['latestVersion'] ??
                    data['version'] ??
                    data['linkId'] ??
                    '')
                .toString()
                .trim();
            final isUpdate = linkType.toLowerCase() == 'app_update';
            final text = isUpdate
                ? (subtitle.isEmpty
                    ? '$title · v${latestVersion.isEmpty ? '?' : latestVersion}'
                    : '$title — $subtitle')
                : (subtitle.isEmpty ? title : '$title — $subtitle');
            final sort = data['sortOrder'];
            return (
              sort: sort is num ? sort.toDouble() : 0.0,
              item: _CrawlItem(
                id: 'crawl_${d.id}',
                text: text,
                linkType: linkType,
                linkId: (data['linkId'] ?? '').toString(),
                latestVersion: latestVersion,
              ),
            );
          })
          .whereType<({double sort, _CrawlItem item})>()
          .toList()
        ..sort((a, b) => a.sort.compareTo(b.sort));

      if (!mounted) return;
      setState(() {
        _adminItems = list.map((e) => e.item).toList();
        _loopWidth = 0;
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _adminItems = const []);
    });
  }

  Future<void> _loadPromos() async {
    try {
      final promos = await PromoService().fetchActivePromos();
      if (!mounted) return;
      setState(() {
        _promoTitles = promos
            .map((p) => p.title.trim())
            .where((t) => t.isNotEmpty)
            .take(10)
            .toList();
        _loopWidth = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _promoTitles = const []);
    }
  }

  void _onLoopWidth(double width) {
    if (width <= 0) return;
    if ((width - _loopWidth).abs() < 1) return;
    _loopWidth = width;
    final ms =
        ((_loopWidth / _pixelsPerSecond) * 1000).round().clamp(8000, 180000);
    _controller
      ..stop()
      ..duration = Duration(milliseconds: ms)
      ..repeat();
  }

  Future<void> _openStoreUpdate(_CrawlItem item) async {
    final target = item.versionLabel;
    final installed = AppVersionInfo.version;
    final storeUrl = defaultTargetPlatform == TargetPlatform.iOS
        ? AppUpdateChecker.appStoreSearchUrl()
        : AppUpdateChecker.playStoreUrl(AppUpdateChecker.playStoreId);

    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update available'),
        content: Text(
          'Latest version: ${target.isEmpty ? 'new build' : 'v$target'}\n'
          'Your version: v$installed\n\n'
          'Update Vero360 from the store to get the latest features and fixes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A00),
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (go != true) return;
    await AppUpdateChecker.openStore(storeUrl);
  }

  void _onTap(_CrawlItem item) {
    final type = item.linkType.toLowerCase().trim();
    if (type == 'app_update') {
      unawaited(_openStoreUpdate(item));
      return;
    }

    Widget? page;
    switch (type) {
      case 'promotion':
      case 'promotions':
        page = const PromotionsPage();
        break;
      case 'announcements':
        page = const NotificationsPage();
        break;
      case 'marketplace':
        page = MarketPage(
          cartService: CartService('', apiPrefix: ApiConfig.apiPrefix),
        );
        break;
      case 'none':
      case '':
        break;
      default:
        page = const PromotionsPage();
    }
    if (page == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
  }

  @override
  void dispose() {
    _crawlSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) return const SizedBox.shrink();

    final needsChipHeight = items.any((i) => i.hasAction);

    return SizedBox(
      height: needsChipHeight ? 22 : 18,
      width: double.infinity,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final dx =
                _loopWidth <= 0 ? 0.0 : -_controller.value * _loopWidth;
            return OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              child: Transform.translate(
                offset: Offset(dx, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CrawlSegment(
                      items: items,
                      onItemTap: _onTap,
                      onMeasured: _onLoopWidth,
                    ),
                    _CrawlSegment(
                      items: items,
                      onItemTap: _onTap,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CrawlSegment extends StatelessWidget {
  final List<_CrawlItem> items;
  final void Function(_CrawlItem) onItemTap;
  final void Function(double width)? onMeasured;

  const _CrawlSegment({
    required this.items,
    required this.onItemTap,
    this.onMeasured,
  });

  @override
  Widget build(BuildContext context) {
    final measure = onMeasured;
    if (measure != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          measure(box.size.width);
        }
      });
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                '•',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          GestureDetector(
            onTap: () => onItemTap(items[i]),
            child: items[i].hasAction
                ? _CrawlActionChip(
                    text: items[i].text,
                    actionLabel: items[i].actionLabel,
                    onAction: () => onItemTap(items[i]),
                  )
                : Text(
                    items[i].text,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.98),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.1,
                      letterSpacing: 0,
                    ),
                  ),
          ),
        ],
        const SizedBox(width: 56),
      ],
    );
  }
}

/// Scrolls with the ticker: message + compact action chip.
class _CrawlActionChip extends StatelessWidget {
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  const _CrawlActionChip({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.98),
            fontWeight: FontWeight.w700,
            fontSize: 12,
            height: 1.1,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(width: 6),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
              child: Text(
                actionLabel,
                style: const TextStyle(
                  color: Color(0xFFEA580C),
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

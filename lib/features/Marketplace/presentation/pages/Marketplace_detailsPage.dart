// lib/Pages/details_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:saver_gallery/saver_gallery.dart';

import 'package:vero360_app/Home/Messages.dart';
import 'package:vero360_app/GeneralPages/checkout_page.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/GernalServices/chat_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/serviceprovider_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/serviceprovider_model.dart';
import 'package:vero360_app/utils/toasthelper.dart';

import '../../../../GeneralPages/video_player_page.dart';

class DetailsPage extends StatefulWidget {
  static const routeName = '/details';

  final MarketplaceDetailModel item;
  final CartService cartService;

  const DetailsPage({
    required this.item,
    required this.cartService,
    super.key,
  });

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _SellerInfo {
  String? businessName,
      openingHours,
      status,
      description,
      logoUrl,
      serviceProviderId;
  double? rating;
  _SellerInfo({
    this.businessName,
    this.openingHours,
    this.status,
    this.description,
    this.rating,
    this.logoUrl,
    this.serviceProviderId,
  });
}

class _Media {
  final String url;
  final bool isVideo;
  _Media._(this.url, this.isVideo);
  factory _Media.image(String u) => _Media._(u, false);
  factory _Media.video(String u) => _Media._(u, true);
}

Widget _buildMarketplaceImage(String src, {BoxFit fit = BoxFit.cover}) {
  final s = src.trim();
  if (s.isEmpty) {
    return Container(
      color: Colors.grey.shade200,
      child: const Icon(
        Icons.broken_image_outlined,
        color: Colors.grey,
      ),
    );
  }

  // HTTP/HTTPS URL
  if (s.startsWith('http://') || s.startsWith('https://')) {
    return Image.network(
      s,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: const Icon(
          Icons.broken_image_outlined,
          color: Colors.grey,
        ),
      ),
    );
  }

  // Try base64 (with or without data: prefix)
  try {
    final base64Part = s.contains(',') ? s.split(',').last : s;
    final bytes = base64Decode(base64Part);
    return Image.memory(
      bytes,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: const Icon(
          Icons.broken_image_outlined,
          color: Colors.grey,
        ),
      ),
    );
  } catch (_) {
    // Fallback: try network again (in case it's some other kind of URL)
    return Image.network(
      s,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: const Icon(
          Icons.broken_image_outlined,
          color: Colors.grey,
        ),
      ),
    );
  }
}

class _DetailsPageState extends State<DetailsPage> {
  // ── Brand (UI only)
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandSoft = Color(0xFFFFE8CC);

  Future<_SellerInfo>? _sellerFuture;
  final TextEditingController _commentController = TextEditingController();
  final FToast _fToast = FToast();

  late final PageController _pc;
  int _page = 0;
  List<_Media> _media = const [];
  Timer? _autoTimer;
  static const _autoInterval = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _pc = PageController();
    _sellerFuture = _loadSeller();
    _fToast.init(context);

    final it = widget.item;
    final images = it.gallery.where((u) => u.toString().trim().isNotEmpty).toList();
    final videos = it.videos.where((u) => u.toString().trim().isNotEmpty).toList();
    final mainImg = it.image.toString().trim();
    _media = [
      if (mainImg.isNotEmpty) _Media.image(mainImg),
      ...images.map((u) => _Media.image(u.toString().trim())),
      ...videos.map((u) => _Media.video(u.toString().trim())),
    ];
    if (_media.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startAutoplay();
      });
    }
  }

  /// Share current product
  void _shareProduct() {
    final item = widget.item;
    final merchantName = item.merchantName ?? item.sellerBusinessName ?? 'A merchant';
    final productUrl = 'https://vero360.app/marketplace/${item.id}';
    final priceStr = NumberFormat('#,###', 'en').format(item.price.truncate());
    Share.share(
      '$merchantName is selling this on Vero360 - Check out ${item.name} - MWK $priceStr\n$productUrl',
    );
  }

  /// Copy product link to clipboard (for pasting in other apps)
  void _copyProductLink() {
    final item = widget.item;
    final productUrl = 'https://vero360.app/marketplace/${item.id}';
    Clipboard.setData(ClipboardData(text: productUrl));
    _toast('Product link copied', Icons.link, _brandOrange);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pc.dispose();
    _commentController.dispose();
    super.dispose();
  }

  // autoplay
  void _startAutoplay() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(_autoInterval, (_) {
      if (!mounted || _media.length <= 1) return;
      final next = (_page + 1) % _media.length;
      _pc.animateToPage(next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut);
    });
  }

  void _stopAutoplay() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  void _next() {
    if (_media.isEmpty) return;
    _stopAutoplay();
    final n = (_page + 1) % _media.length;
    _pc.animateToPage(n,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut);
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _media.length > 1) _startAutoplay();
    });
  }

  void _prev() {
    if (_media.isEmpty) return;
    _stopAutoplay();
    final p = (_page - 1 + _media.length) % _media.length;
    _pc.animateToPage(p,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut);
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _media.length > 1) _startAutoplay();
    });
  }

  // seller/data
  Future<_SellerInfo> _loadSeller() async {
    final i = widget.item;
    final info = _SellerInfo(
      businessName: i.sellerBusinessName,
      openingHours: i.sellerOpeningHours,
      status: i.sellerStatus,
      description: i.sellerBusinessDescription,
      rating: i.sellerRating,
      logoUrl: i.sellerLogoUrl,
      serviceProviderId: i.serviceProviderId,
    );

    final missing = info.businessName == null ||
        info.openingHours == null ||
        info.status == null ||
        info.description == null ||
        info.rating == null ||
        info.logoUrl == null;

    final spId = info.serviceProviderId?.trim();
    if (missing && spId != null && spId.isNotEmpty) {
      try {
        final ServiceProvider? sp =
            await ServiceProviderServicess.fetchByNumber(spId);
        if (sp != null) {
          info.businessName ??= sp.businessName;
          info.openingHours ??= sp.openingHours;
          info.status ??= sp.status;
          info.description ??= sp.businessDescription;
          info.logoUrl ??= sp.logoUrl;
          final r = sp.rating;
          if (info.rating == null && r != null) {
            info.rating = (r as num).toDouble();
          }
        }
      } catch (_) {}
    }
    return info;
  }

  Future<String?> _readAuthToken() async => AuthHandler.getTokenForApi();

  Future<bool> _requireLogin() async {
    final t = await _readAuthToken();
    final ok = t != null;
    if (!ok) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to chat with merchant.',
        isSuccess: false,
        errorMessage: '',
      );
    }
    return ok;
  }

  Future<String?> getMyUserId() async {
    final sp = await SharedPreferences.getInstance();
    final token = sp.getString('jwt_token') ?? sp.getString('token');
    if (token == null || token.isEmpty) return null;
    final claims = JwtDecoder.decode(token);
    final id = (claims['sub'] ?? claims['id'])?.toString();
    return (id != null && id.isNotEmpty) ? id : null;
  }

  Future<void> _goToCheckout(MarketplaceDetailModel item) async {
    final prefs = await SharedPreferences.getInstance();
    final _ = prefs.getInt('userId'); // kept as-is
    // ignore: use_build_context_synchronously
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CheckoutPage(item: item)),
    );
  }

  void _toast(String msg, IconData icon, Color color) {
    _fToast.showToast(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              msg,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ]),
      ),
      gravity: ToastGravity.CENTER,
      toastDuration: const Duration(seconds: 2),
    );
  }

  String? _closingFromHours(String? openingHours) {
    if (openingHours == null || openingHours.trim().isEmpty) return null;
    final parts = openingHours.replaceAll('–', '-').split('-');
    return parts.length == 2 ? parts[1].trim() : null;
  }

  String _formatTimeAgo(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return m == 1 ? '1 min ago' : '$m mins ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return h == 1 ? '1 hr ago' : '$h hrs ago';
    }
    if (diff.inDays < 7) {
      final d = diff.inDays;
      return d == 1 ? '1 day ago' : '$d days ago';
    }
    return DateFormat('d MMMM yyyy').format(time);
  }

  Widget _infoRow(String label, String? value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 8),
        ],
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            (value ?? '').isNotEmpty ? value! : '—',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  Widget _statusChip(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    Color bg = Colors.grey.shade200, fg = Colors.black87;
    if (s == 'open') {
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
    } else if (s == 'closed') {
      bg = Colors.red.shade50;
      fg = Colors.red.shade700;
    } else if (s == 'busy') {
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade800;
    }
    return Chip(
      label: Text((status ?? '—').toUpperCase()),
      backgroundColor: bg,
      labelStyle: TextStyle(color: fg, fontWeight: FontWeight.w700),
      visualDensity: VisualDensity.compact,
    );
  }

  String _fmtRating(double? r) {
    if (r == null) return '—';
    final whole = r.truncateToDouble();
    return r == whole ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  }

  Widget _ratingStars(double? rating) {
    final rr = ((rating ?? 0).clamp(0, 5)).toDouble();
    final filled = rr.floor();
    final hasHalf = (rr - filled) >= 0.5 && filled < 5;
    final empty = 5 - filled - (hasHalf ? 1 : 0);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (int i = 0; i < filled; i++)
        const Icon(Icons.star, size: 16, color: Colors.amber),
      if (hasHalf)
        const Icon(Icons.star_half, size: 16, color: Colors.amber),
      for (int i = 0; i < empty; i++)
        const Icon(Icons.star_border, size: 16, color: Colors.amber),
      const SizedBox(width: 6),
      Text(_fmtRating(rr),
          style: const TextStyle(fontWeight: FontWeight.w600)),
    ]);
  }

  void _openVideo(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoPlayerPage(url: url)),
    );
  }

  /// Open fullscreen image viewer with watermark (merchant name + Vero360App) and download.
  void _openImageViewer(String imageUrl, {String? merchantName}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(
          imageUrl: imageUrl,
          merchantName: merchantName ?? widget.item.sellerBusinessName ?? widget.item.merchantName ?? 'Merchant',
        ),
      ),
    );
  }

  Future<void> _openChat(MarketplaceDetailModel item) async {
    if (!await _requireLogin()) return;

    final peerAppId =
        (item.serviceProviderId ?? item.sellerUserId ?? '').trim();
    if (peerAppId.isEmpty) {
      _toast('Seller chat unavailable', Icons.info_outline, Colors.orange);
      return;
    }

    final sellerName = item.sellerBusinessName ?? 'Seller';
    final sellerAvatar = item.sellerLogoUrl ?? '';

    await ChatService.ensureFirebaseAuth();
    final me = await ChatService.myAppUserId();
    await ChatService.ensureThread(
      myAppId: me,
      peerAppId: peerAppId,
      peerName: sellerName,
      peerAvatar: sellerAvatar,
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessagePage(
          peerAppId: peerAppId,
          peerName: sellerName,
          peerAvatarUrl: sellerAvatar,
          peerId: '',
        ),
      ),
    );
  }

  /// Navigate to a page that shows all products from this merchant.
  /// You need to implement `MerchantProductsPage` + fetching by merchantId.
  void _openMerchantProducts(
      {required String merchantId,
      required String merchantName}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MerchantProductsPage(
          merchantId: merchantId,
          merchantName: merchantName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Item Details"),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            onPressed: _copyProductLink,
            tooltip: 'Copy link',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareProduct,
            tooltip: 'Share product',
          ),
        ],
      ),
      body: FutureBuilder<_SellerInfo>(
        future: _sellerFuture ??= _loadSeller(),
        builder: (context, snapshot) {
          final s = snapshot.data;
          final businessName = s?.businessName;
          final status = s?.status;
          final openingHours = s?.openingHours;
          final closing = _closingFromHours(openingHours);
          final rating = s?.rating;
          final businessDesc = s?.description;
          final logo = s?.logoUrl;

          final hasMerchant =
              (item.merchantId != null && item.merchantId!.isNotEmpty) ||
                  (item.serviceProviderId != null &&
                      item.serviceProviderId!.isNotEmpty);

          final merchantId =
              item.merchantId ?? item.serviceProviderId ?? '';
          final merchantDisplayName =
              item.merchantName ?? businessName ?? 'Merchant';

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                // ----- MEDIA CAROUSEL -----
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: PageView.builder(
                          controller: _pc,
                          physics: _media.length > 1
                              ? const BouncingScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          itemCount: _media.length,
                          onPageChanged: (i) {
                            setState(() => _page = i);
                            if (_media.length > 1) _startAutoplay();
                          },
                          itemBuilder: (_, i) {
                            final m = _media[i];
                            if (!m.isVideo) {
                              return InkWell(
                                onTap: () => _openImageViewer(
                                  m.url,
                                  merchantName: widget.item.merchantName ??
                                      widget.item.sellerBusinessName,
                                ),
                                child: _buildMarketplaceImage(
                                  m.url,
                                  fit: BoxFit.cover,
                                ),
                              );
                            }
                            return InkWell(
                              onTap: () => _openVideo(m.url),
                              child: Stack(
                                children: const [
                                  ColoredBox(
                                    color: Colors.black26,
                                  ),
                                  Center(
                                    child: Icon(
                                      Icons.play_circle_fill,
                                      size: 64,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (_media.length > 1) ...[
                        Positioned(
                          left: 8,
                          top: 0,
                          bottom: 0,
                          child: _NavBtn(
                            icon: Icons.chevron_left,
                            onTap: _prev,
                          ),
                        ),
                        Positioned(
                          right: 8,
                          top: 0,
                          bottom: 0,
                          child: _NavBtn(
                            icon: Icons.chevron_right,
                            onTap: _next,
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children:
                                List.generate(_media.length, (i) {
                              final active = i == _page;
                              return AnimatedContainer(
                                duration: const Duration(
                                    milliseconds: 200),
                                margin:
                                    const EdgeInsets.symmetric(
                                        horizontal: 3),
                                width: active ? 18 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: active
                                      ? _brandOrange
                                      : Colors.white70,
                                  borderRadius:
                                      BorderRadius.circular(20),
                                  border: Border.all(
                                      color: Colors.black26),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ----- TEXTS + CHAT BUTTON -----
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _brandSoft,
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: Border.all(
                                  color: _brandOrange),
                            ),
                            child: Text(
                              'MWK ${NumberFormat('#,###', 'en').format(item.price.truncate())}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (item.description.isNotEmpty)
                            Text(
                              item.description,
                              style:
                                  const TextStyle(height: 1.3),
                            ),
                          if (merchantDisplayName.isNotEmpty || item.createdAt != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              item.createdAt != null
                                  ? 'Posted by $merchantDisplayName • ${_formatTimeAgo(item.createdAt!)}'
                                  : 'Posted by $merchantDisplayName',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onPressed: () => _openChat(item),
                      icon:
                          const Icon(Icons.message_rounded),
                      label: const Text('Chat'),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ----- MERCHANT CARD (full details) -----
                Card(
                  elevation: 6,
                  shadowColor: Colors.black12,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Merchant photo (logo URL from seller info or item)
                            if ((logo ?? item.sellerLogoUrl) != null &&
                                (logo ?? item.sellerLogoUrl)!.trim().isNotEmpty)
                              CircleAvatar(
                                radius: 18,
                                backgroundImage: NetworkImage(
                                    (logo ?? item.sellerLogoUrl)!.trim()),
                                onBackgroundImageError: (_, __) {},
                              ),
                            if ((logo ?? item.sellerLogoUrl) != null &&
                                (logo ?? item.sellerLogoUrl)!.trim().isNotEmpty)
                              const SizedBox(width: 10),
                            const Icon(Icons.storefront_rounded,
                                size: 20, color: Colors.black87),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Posted by ${(item.merchantName ?? businessName ?? '').trim().isEmpty ? '—' : merchantDisplayName}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _ratingStars(rating),
                            const SizedBox(width: 8),
                            _statusChip(status),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _infoRow(
                          'Business name',
                          businessName ?? item.sellerBusinessName ?? item.merchantName,
                          icon: Icons.badge_rounded,
                        ),
                        _infoRow('Closing hours', closing,
                            icon: Icons.access_time_rounded),
                        _infoRow(
                          'Status',
                          (status ?? '').isEmpty ? '—' : status!.toUpperCase(),
                          icon: Icons.info_outline_rounded,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Business description',
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (businessDesc ?? '').isNotEmpty ? businessDesc! : '—',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),

                // ----- VIEW MERCHANT PRODUCTS BUTTON -----
                if (hasMerchant &&
                    merchantId.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(
                        Icons.store_mall_directory_outlined,
                      ),
                      label: Text(
                        'View more from $merchantDisplayName',
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                        ),
                        side: BorderSide(
                            color: _brandOrange),
                        foregroundColor: _brandOrange,
                      ),
                      onPressed: () {
                        _openMerchantProducts(
                          merchantId: merchantId,
                          merchantName:
                              merchantDisplayName,
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _brandOrange,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(
                              vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w700),
                    ),
                    onPressed: () =>
                        _goToCheckout(widget.item),
                    icon: const Icon(
                        Icons.shopping_bag_outlined),
                    label:
                        const Text("Continue to checkout"),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black38,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }
}

/// Fullscreen image viewer with watermark (merchant name + Vero360App) and download.
class _FullScreenImageViewer extends StatefulWidget {
  const _FullScreenImageViewer({
    required this.imageUrl,
    required this.merchantName,
  });
  final String imageUrl;
  final String merchantName;

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  bool _saving = false;

  Future<void> _downloadImage() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final uri = Uri.tryParse(widget.imageUrl);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        if (mounted) {
          ToastHelper.showCustomToast(
            context,
            'Cannot download this image',
            isSuccess: false,
            errorMessage: '',
          );
        }
        return;
      }
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        if (mounted) {
          ToastHelper.showCustomToast(
            context,
            'Failed to load image',
            isSuccess: false,
            errorMessage: '',
          );
        }
        return;
      }
      // Decode image, draw watermark on it, then save (watermark only on saved file)
      Uint8List bytesToSave = res.bodyBytes;
      try {
        final codec = await ui.instantiateImageCodec(res.bodyBytes);
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final w = image.width.toDouble();
        final h = image.height.toDouble();
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final src = Rect.fromLTWH(0, 0, w, h);
        canvas.drawImageRect(image, src, src, Paint());
        image.dispose();
        // Watermark: app logo + merchant name + Vero360App
        const double fontSize = 32;
        const double fontSize2 = 24;
        const double logoHeight = 58;
        const double leftPad = 24;
        final maxW = w - 48;
        final bottomY = h - 24 - fontSize - 6 - fontSize2;

        // 1) App logo (assets/logo_mark.png), expanded a bit
        try {
          final logoBytes = await rootBundle.load('assets/logo_mark.png');
          final logoCodec = await ui.instantiateImageCodec(
            logoBytes.buffer.asUint8List(logoBytes.offsetInBytes, logoBytes.lengthInBytes),
          );
          final logoFrame = await logoCodec.getNextFrame();
          final logoImage = logoFrame.image;
          final lw = logoImage.width.toDouble();
          final lh = logoImage.height.toDouble();
          if (lw > 0 && lh > 0) {
            final scale = logoHeight / lh;
            final scaledW = lw * scale;
            final logoRect = Rect.fromLTWH(leftPad, bottomY - logoHeight - 4, scaledW, logoHeight);
            canvas.drawImageRect(
              logoImage,
              Rect.fromLTWH(0, 0, lw, lh),
              logoRect,
              Paint()..filterQuality = ui.FilterQuality.medium,
            );
            logoImage.dispose();
          }
        } catch (_) {}

        // 2) Merchant name + Vero360App text
        final tp1 = TextPainter(
          text: TextSpan(
            text: widget.merchantName,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(color: Colors.black87, blurRadius: 4, offset: const Offset(1, 1)),
                Shadow(color: Colors.black54, blurRadius: 2, offset: const Offset(0, 0)),
              ],
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout(maxWidth: maxW);
        final tp2 = TextPainter(
          text: const TextSpan(
            text: 'Vero360App',
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize2,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(1, 1)),
                Shadow(color: Colors.black54, blurRadius: 2, offset: Offset(0, 0)),
              ],
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout(maxWidth: maxW);
        tp1.paint(canvas, Offset(leftPad, bottomY));
        tp2.paint(canvas, Offset(leftPad, bottomY + fontSize + 6));

        final picture = recorder.endRecording();
        final outImage = await picture.toImage(w.round(), h.round());
        final byteData = await outImage.toByteData(format: ui.ImageByteFormat.png);
        outImage.dispose();
        if (byteData != null) {
          bytesToSave = byteData.buffer.asUint8List();
        }
      } catch (_) {
        // If watermarking fails, save original bytes
      }
      final fileName = 'vero360_${DateTime.now().millisecondsSinceEpoch}.png';
      final result = await SaverGallery.saveImage(
        bytesToSave,
        quality: 100,
        extension: 'png',
        fileName: fileName,
        androidRelativePath: 'Pictures/Vero360',
        skipIfExists: false,
      );
      if (mounted) {
        if (result.isSuccess) {
          ToastHelper.showCustomToast(
            context,
            'Image saved to gallery',
            isSuccess: true,
            errorMessage: '',
          );
        } else {
          ToastHelper.showCustomToast(
            context,
            result.errorMessage ?? 'Save failed',
            isSuccess: false,
            errorMessage: '',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Download failed',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Center(
              child: _buildMarketplaceImage(
                widget.imageUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
          // Top bar: close
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          // Download button
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: _saving ? null : _downloadImage,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_saving ? 'Saving…' : 'Download'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
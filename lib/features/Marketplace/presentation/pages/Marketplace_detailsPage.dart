// lib/Pages/details_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_reviews_page.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:saver_gallery/saver_gallery.dart';

import 'package:vero360_app/Home/MessagePageBackendApi.dart';
import 'package:vero360_app/GeneralModels/chat_product_context.dart';
import 'package:vero360_app/GeneralPages/checkout_page.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/serviceprovider_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/serviceprovider_model.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

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
  int? backendMerchantId;
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

  // HTTP/HTTPS URL (disk-cached, full resolution)
  if (s.startsWith('http://') || s.startsWith('https://')) {
    return ResilientCachedNetworkImage(url: s, fit: fit);
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
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return ResilientCachedNetworkImage(url: s, fit: fit);
    }
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
  static const Color _bg = Color(0xFFF7F8FA);
  static const Color _ink = Color(0xFF101010);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFECEEF2);

  Future<_SellerInfo>? _sellerFuture;
  final TextEditingController _commentController = TextEditingController();
  final FToast _fToast = FToast();

  late final PageController _pc;
  int _page = 0;
  List<_Media> _media = const [];
  Timer? _autoTimer;
  static const _autoInterval = Duration(seconds: 4);
  bool _openingChat = false;

  @override
  void initState() {
    super.initState();
    unawaited(BackendChatService.ensureAuth().catchError((_) {}));
    unawaited(BackendMessagingSocket.connect().catchError((_) {}));
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
          if (sp.id != null && sp.id! > 0) {
            info.backendMerchantId = sp.id;
          }
          final r = sp.rating;
          if (info.rating == null && r != null) {
            info.rating = (r as num).toDouble();
          }
        }
      } catch (_) {}
    }

    if (info.backendMerchantId == null) {
      for (final raw in [i.merchantId, i.sellerUserId]) {
        final key = raw?.trim();
        if (key == null || key.isEmpty) continue;
        if (RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(key)) continue;
        try {
          final sp = await ServiceProviderServicess.fetchByNumber(key);
          if (sp?.id != null && sp!.id! > 0) {
            info.backendMerchantId = sp.id;
            break;
          }
        } catch (_) {}
      }
    }

    // Fallback profile data source (same family as merchant dashboard):
    // 1) marketplace_merchants/{merchantUid}
    // 2) users/{merchantUid}
    final merchantUid = (i.merchantId ?? '').trim();
    if (merchantUid.isNotEmpty) {
      try {
        final mDoc = await FirebaseFirestore.instance
            .collection('marketplace_merchants')
            .doc(merchantUid)
            .get();
        if (mDoc.exists) {
          final m = mDoc.data() ?? <String, dynamic>{};
          info.businessName ??=
              (m['businessName'] ?? m['merchantName'] ?? '').toString().trim().isEmpty
                  ? null
                  : (m['businessName'] ?? m['merchantName']).toString().trim();
          info.status ??= (m['status'] ?? m['verificationStatus'] ?? '')
              .toString()
              .trim()
              .isEmpty
              ? null
              : (m['status'] ?? m['verificationStatus']).toString().trim();
          final p = (m['profilePicture'] ?? m['profilepicture'] ?? '')
              .toString()
              .trim();
          if (p.isNotEmpty) info.logoUrl ??= p;
        }
      } catch (_) {}

      try {
        final uDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(merchantUid)
            .get();
        if (uDoc.exists) {
          final u = uDoc.data() ?? <String, dynamic>{};
          final p = (u['profilepicture'] ??
                  u['profilePicture'] ??
                  u['photoUrl'] ??
                  u['photoURL'] ??
                  '')
              .toString()
              .trim();
          if (p.isNotEmpty) info.logoUrl ??= p;
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

  Widget _statusChip(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    Color bg = Colors.grey.shade200, fg = Colors.black87;
    var isPending = false;
    if (s == 'open') {
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
    } else if (s == 'closed') {
      bg = Colors.red.shade50;
      fg = Colors.red.shade700;
    } else if (s == 'busy') {
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade800;
    } else if (s == 'pending') {
      isPending = true;
      bg = Colors.orange.shade100;
      fg = Colors.orange.shade900;
    }
    return Chip(
      label: Text((status ?? '—').toUpperCase()),
      backgroundColor: bg,
      labelStyle: TextStyle(
        color: fg,
        fontWeight: FontWeight.w700,
        fontSize: isPending ? 11 : 12,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.symmetric(horizontal: isPending ? 2 : 4),
    );
  }

  String _fmtRating(double? r) {
    if (r == null) return '—';
    final whole = r.truncateToDouble();
    return r == whole ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  }

  String _formatTimeAgo(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m ${m == 1 ? 'min' : 'mins'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h ${h == 1 ? 'hr' : 'hrs'} ago';
    }
    if (diff.inDays < 7) {
      final d = diff.inDays;
      return '$d ${d == 1 ? 'day' : 'days'} ago';
    }

    final weeks = (diff.inDays / 7).floor();
    if (weeks < 4) return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';

    final months = (diff.inDays / 30).floor();
    if (months < 12) return '$months ${months == 1 ? 'month' : 'months'} ago';

    final years = (diff.inDays / 365).floor();
    return '$years ${years == 1 ? 'year' : 'years'} ago';
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

  void _openMerchantReviews({
    required String merchantId,
    required String merchantName,
    String? logoUrl,
    double? rating,
    String? serviceProviderId,
    String? sellerUserId,
    int? merchantBackendId,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MerchantReviewsPage(
          merchantId: merchantId,
          merchantName: merchantName,
          logoUrl: logoUrl,
          rating: rating,
          serviceProviderId: serviceProviderId,
          sellerUserId: sellerUserId,
          merchantBackendId: merchantBackendId,
        ),
      ),
    );
  }

  Widget _buildMerchantCard({
    required MarketplaceDetailModel item,
    required String merchantDisplayName,
    required String merchantId,
    required bool hasMerchant,
    String? businessName,
    String? status,
    double? rating,
    String? businessDesc,
    String? logo,
    int? merchantBackendId,
  }) {
    const ink = Color(0xFF101010);
    const muted = Color(0xFF6B7280);
    const border = Color(0xFFECEEF2);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _merchantAvatar(logo ?? item.sellerLogoUrl, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchantDisplayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _ratingStars(rating),
                          const SizedBox(width: 8),
                          Text(
                            _fmtRating(rating ?? 0),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: ink,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _merchantDetailRow(
                    icon: Icons.badge_outlined,
                    label: 'Business name',
                    value: businessName ??
                        item.sellerBusinessName ??
                        item.merchantName,
                  ),
                  const SizedBox(height: 8),
                  _merchantDetailRow(
                    icon: Icons.info_outline_rounded,
                    label: 'Status',
                    value: (status ?? '').isEmpty ? '—' : status!.toUpperCase(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Business description',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              (businessDesc ?? '').trim().isNotEmpty ? businessDesc!.trim() : '—',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: ink,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Material(
              color: const Color(0xFFFFF8F0),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: hasMerchant && merchantId.trim().isNotEmpty
                    ? () => _openMerchantReviews(
                          merchantId: merchantId,
                          merchantName: merchantDisplayName,
                          logoUrl: logo ?? item.sellerLogoUrl,
                          rating: rating,
                          serviceProviderId: item.serviceProviderId,
                          sellerUserId: item.sellerUserId,
                          merchantBackendId: merchantBackendId,
                        )
                    : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _brandOrange.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _brandOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.rate_review_outlined,
                          color: _brandOrange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reviews & Ratings',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'See what customers are saying',
                              style: TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey.shade500,
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
  }

  Widget _merchantDetailRow({
    required IconData icon,
    required String label,
    required String? value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
        Expanded(
          child: Text(
            (value ?? '').trim().isEmpty ? '—' : value!.trim(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF101010),
            ),
          ),
        ),
      ],
    );
  }

  Widget _merchantAvatar(String? raw, {double size = 36}) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: const Color(0xFFFFF4E5),
        child: Icon(
          Icons.storefront_outlined,
          color: _brandOrange,
          size: size * 0.45,
        ),
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFF0F2F5),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: _buildMarketplaceImage(s, fit: BoxFit.cover),
        ),
      ),
    );
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
    if (_openingChat) return;
    if (!await _requireLogin()) return;
    if (!mounted) return;

    setState(() => _openingChat = true);

    try {
      final myId = await BackendChatService.getUserId();

      final ownerId = int.tryParse((item.sellerUserId ?? '').trim());
      final sqlItemId = item.id > 0 ? item.id : null;

      final result = await BackendChatService.startMerchantChat(
        sqlItemId: sqlItemId,
        ownerId: ownerId,
        sellerUserId: item.sellerUserId,
        serviceProviderId: item.serviceProviderId,
        merchantId: item.merchantId,
        myUserId: myId,
      );

      if (kDebugMode) {
        debugPrint('[_openChat] Opened chat ${result.chat.id} with seller');
      }

      if (!mounted) return;

      final sellerName = item.sellerBusinessName ?? item.merchantName ?? 'Seller';
      final sellerAvatar = item.sellerLogoUrl ?? '';
      final productContext = ChatProductContext(
        productId: item.id.toString(),
        name: item.name,
        image: item.image,
        price: item.price,
        description: item.description,
        merchantId: (item.merchantId ?? item.serviceProviderId ?? '').trim().isEmpty
            ? null
            : (item.merchantId ?? item.serviceProviderId),
      );

      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => MessagePageBackendApi(
            peerId: result.chat.id,
            peerName: sellerName,
            peerAvatarUrl: sellerAvatar,
            productContext: productContext,
            peerMerchantId: item.merchantId ?? item.serviceProviderId,
            peerUserId: result.sellerId,
            sendProductEnquiry: true,
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[_openChat] Exception: $e');
      if (mounted) {
        _toast('Error opening chat: ${e.toString()}', Icons.error, Colors.red);
      }
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
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

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text(
        'Item Details',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: _ink,
          letterSpacing: -0.3,
        ),
      ),
      centerTitle: false,
      backgroundColor: Colors.white,
      foregroundColor: _ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.white,
      actions: [
        IconButton(
          icon: const Icon(Icons.link_rounded),
          onPressed: _copyProductLink,
          tooltip: 'Copy link',
        ),
        IconButton(
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: _shareProduct,
          tooltip: 'Share product',
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildHeroGallery() {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: PageView.builder(
              controller: _pc,
              physics: _media.length > 1
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: _media.isEmpty ? 1 : _media.length,
              onPageChanged: (i) {
                setState(() => _page = i);
                if (_media.length > 1) _startAutoplay();
              },
              itemBuilder: (_, i) {
                if (_media.isEmpty) {
                  return ColoredBox(
                    color: const Color(0xFFF0F2F5),
                    child: Icon(
                      Icons.image_outlined,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                  );
                }
                final m = _media[i];
                if (!m.isVideo) {
                  return InkWell(
                    onTap: () => _openImageViewer(
                      m.url,
                      merchantName: widget.item.merchantName ??
                          widget.item.sellerBusinessName,
                    ),
                    child: _buildMarketplaceImage(m.url, fit: BoxFit.cover),
                  );
                }
                return InkWell(
                  onTap: () => _openVideo(m.url),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 40,
                            color: _brandOrange,
                          ),
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
              top: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_page + 1} / ${_media.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_media.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active
                          ? _brandOrange
                          : Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductCard({
    required MarketplaceDetailModel item,
    required String merchantDisplayName,
  }) {
    final price =
        'MWK ${NumberFormat('#,###', 'en').format(item.price.truncate())}';
    final category = (item.category ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (category.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _brandSoft.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                category.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _brandOrange,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            item.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _ink,
              height: 1.2,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9A2E), Color(0xFFFF8A00)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _brandOrange.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  price,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (item.location.trim().isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.location.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'About this item',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _muted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.description,
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: _ink,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          if (merchantDisplayName.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.createdAt != null
                        ? 'Posted by $merchantDisplayName • ${_formatTimeAgo(item.createdAt!)}'
                        : 'Posted by $merchantDisplayName',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChatButton(MarketplaceDetailModel item) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: _brandOrange,
          side: BorderSide(color: _brandOrange.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: _openingChat ? null : () => _openChat(item),
        icon: _openingChat
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _brandOrange,
                ),
              )
            : const Icon(Icons.chat_bubble_outline_rounded),
        label: Text(
          _openingChat ? 'Opening chat…' : 'Chat with seller',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildMerchantProductsButton({
    required String merchantId,
    required String merchantDisplayName,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openMerchantProducts(
            merchantId: merchantId,
            merchantName: merchantDisplayName,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _brandSoft.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    color: _brandOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'More from $merchantDisplayName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Browse all products from this seller',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(MarketplaceDetailModel item) {
    final price =
        'MWK ${NumberFormat('#,###', 'en').format(item.price.truncate())}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 12,
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _goToCheckout(item),
                  icon: const Icon(Icons.shopping_bag_outlined, size: 20),
                  label: const Text(
                    'Checkout',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: _ink,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      bottomNavigationBar: _buildBottomBar(item),
      body: FutureBuilder<_SellerInfo>(
        future: _sellerFuture ??= _loadSeller(),
        builder: (context, snapshot) {
          final s = snapshot.data;
          final businessName = s?.businessName;
          final status = s?.status;
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
              businessName ?? item.sellerBusinessName ?? item.merchantName ?? 'Merchant';

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _buildHeroGallery(),
              const SizedBox(height: 16),
              _buildProductCard(
                item: item,
                merchantDisplayName: merchantDisplayName,
              ),
              const SizedBox(height: 12),
              _buildChatButton(item),
              const SizedBox(height: 24),
              _sectionLabel('Seller'),
              _buildMerchantCard(
                item: item,
                merchantDisplayName: merchantDisplayName,
                merchantId: merchantId,
                hasMerchant: hasMerchant,
                businessName: businessName,
                status: status,
                rating: rating,
                businessDesc: businessDesc,
                logo: logo,
                merchantBackendId: s?.backendMerchantId,
              ),
              if (hasMerchant && merchantId.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildMerchantProductsButton(
                  merchantId: merchantId,
                  merchantDisplayName: merchantDisplayName,
                ),
              ],
              const SizedBox(height: 8),
            ],
          );
        },
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
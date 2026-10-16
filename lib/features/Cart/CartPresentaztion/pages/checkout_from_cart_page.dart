import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GeneralPages/address.dart';
import 'package:vero360_app/GeneralPages/checkout_page.dart' show DeliveryType;
import 'package:vero360_app/GeneralModels/address_model.dart';
import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/MarkeplaceMerchantServices/postlatestArrivalservices.dart';
import 'package:vero360_app/features/Restraurants/Models/food_order_model.dart';
import 'package:vero360_app/features/Restraurants/Models/food_order_number.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_courier_dispatch.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/food_my_orders_page.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/restaurant_service.dart';
import 'package:vero360_app/GernalServices/address_service.dart';
import 'package:vero360_app/GernalServices/buyer_commission.dart';
import 'package:vero360_app/GernalServices/order_escrow_service.dart';
import 'package:vero360_app/GernalServices/pawapay_payment.dart';
import 'package:vero360_app/GernalServices/order_party_notification_service.dart';
import 'package:vero360_app/GernalServices/order_service.dart' as order_svc;
import 'package:vero360_app/GernalServices/vero_rewards_service.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/Home/myorders.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierService/courier_city.dart';
import 'package:vero360_app/utils/merchant_contact_display.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/modern_confirm_dialog.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';
import 'package:vero360_app/widgets/vero_spin_reward_prompt.dart';
class CheckoutFromCartPage extends StatefulWidget {
  final List<CartModel> items;
  final bool foodCheckoutMode;

  const CheckoutFromCartPage({super.key, required this.items})
      : foodCheckoutMode = false;

  const CheckoutFromCartPage.food({super.key, required this.items})
      : foodCheckoutMode = true;

  @override
  State<CheckoutFromCartPage> createState() => _CheckoutFromCartPageState();
}

class _CheckoutFromCartPageState extends State<CheckoutFromCartPage> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const Color _brandSoft = Color(0xFFFFE8CC);
  static const Color _pageBg = Color(0xFFF4F6FA);

  bool _paying = false;
  DeliveryType _deliveryType = DeliveryType.speed;

  late List<CartModel> _items;
  final Map<String, TextEditingController> _qtyCtrls = {};

  final _addrSvc = AddressService();
  Address? _defaultAddr;
  bool _loadingAddr = true;
  bool _loggedIn = false;
  bool _merchantsInLilongwe = false;

  /// raw image string → resolved http URL (or empty if failed / not network)
  final Map<String, String> _resolvedHttpUrls = {};
  final Map<String, Uint8List> _decodedBytes = {};

  late final NumberFormat _mwkFmt =
      NumberFormat.currency(locale: 'en_US', symbol: 'MWK ', decimalDigits: 0);
  String _mwk(num v) => _mwkFmt.format(v);

  String _qtyKey(CartModel it) => '${it.item}_${it.merchantId}';

  double get _subtotal =>
      _items.fold(0.0, (sum, item) => sum + (item.price * item.quantity));

  BuyerCommissionQuote get _commissionQuote => BuyerCommission.quote(_subtotal);

  /// Buyer pays the seller's price plus commission. Commission is not taken
  /// from the seller.
  double get _total => max(0.0, _commissionQuote.buyerTotal);

  int? get _maxFoodPrepMinutes {
    if (!_isFoodCheckout) return null;
    var max = 0;
    for (final it in _items) {
      final m = it.prepTimeMinutes;
      if (m != null && m > max) max = m;
    }
    return max > 0 ? max : null;
  }

  String get _itemsSectionSubtitle {
    final count =
        '${_items.length} item${_items.length == 1 ? '' : 's'} in this order';
    final prep = _maxFoodPrepMinutes;
    if (prep != null) return '$count · up to $prep min prep';
    return count;
  }

  bool get _isFoodCheckout =>
      widget.foodCheckoutMode ||
      (_items.isNotEmpty && _items.every((e) => e.isFood));

  bool get _hasMixedCart =>
      _items.any((e) => e.isFood) && _items.any((e) => !e.isFood);

  CourierServiceCity? get _foodCourierCity {
    if (!_buyerInLilongwe || !_merchantsInLilongwe) return null;
    return CourierServiceCity.lilongwe;
  }

  bool get _buyerInLilongwe {
    final addr = _defaultAddr;
    if (addr == null) return false;
    return CourierCityHelper.isLilongwe(
      text: [addr.city, addr.formattedAddress, addr.description].join(' '),
      lat: addr.lat,
      lng: addr.lng,
    );
  }

  bool get _veroCourierAvailable {
    if (_isFoodCheckout) return _foodCourierCity != null;
    return _buyerInLilongwe && _merchantsInLilongwe;
  }

  void _clampDeliveryType() {
    if (_isFoodCheckout) return;
    if (_deliveryType == DeliveryType.veroCourier && !_veroCourierAvailable) {
      _deliveryType = DeliveryType.speed;
    }
  }

  String _deliveryLabel(DeliveryType d) {
    switch (d) {
      case DeliveryType.speed:
        return 'Speed';
      case DeliveryType.cts:
        return 'CTS';
      case DeliveryType.ankolo:
        return 'Ankolo';
      case DeliveryType.smart:
        return 'Smart';
      case DeliveryType.veroCourier:
        return 'Vero Courier';
      case DeliveryType.pickup:
        return 'Pickup';
    }
  }

  String _deliverySubtitle(DeliveryType d) {
    switch (d) {
      case DeliveryType.speed:
        return 'Fast delivery';
      case DeliveryType.cts:
        return 'Standard';
      case DeliveryType.ankolo:
        return 'Online tracking';
      case DeliveryType.smart:
        return 'Online tracking';
      case DeliveryType.veroCourier:
        return 'Lilongwe same-city';
      case DeliveryType.pickup:
        return 'Collect at shop';
    }
  }

  IconData _deliveryIcon(DeliveryType d) {
    switch (d) {
      case DeliveryType.speed:
        return Icons.bolt_rounded;
      case DeliveryType.cts:
        return Icons.local_shipping_rounded;
      case DeliveryType.ankolo:
        return Icons.local_shipping_outlined;
      case DeliveryType.smart:
        return Icons.electric_moped_rounded;
      case DeliveryType.veroCourier:
        return Icons.delivery_dining_rounded;
      case DeliveryType.pickup:
        return Icons.storefront_rounded;
    }
  }

  Widget _section({required String title, String? subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: _brandNavy,
              letterSpacing: -0.2,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _stepsHeader() {
    Widget step(String label, bool active) {
      return Expanded(
        child: Column(
          children: [
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: active ? _brandOrange : Colors.black.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: active ? _brandNavy : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        step('Order', true),
        const SizedBox(width: 8),
        step('Delivery', true),
        const SizedBox(width: 8),
        step('Pay', false),
      ],
    );
  }

  Widget _courierTile(DeliveryType type, {bool locked = false}) {
    final selected = _deliveryType == type;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: locked ? null : () => setState(() => _deliveryType = type),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          decoration: BoxDecoration(
            color: selected ? _brandSoft : const Color(0xFFF8F9FC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _brandOrange
                  : Colors.black.withValues(alpha: 0.08),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _deliveryIcon(type),
                    size: 18,
                    color: selected ? _brandOrange : _brandNavy,
                  ),
                  const Spacer(),
                  if (selected)
                    const Icon(Icons.check_circle_rounded,
                        size: 16, color: _brandOrange),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _deliveryLabel(type),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: _brandNavy,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _deliverySubtitle(type),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _courierGrid() {
    if (_isFoodCheckout) {
      return _courierTile(DeliveryType.veroCourier, locked: true);
    }
    final options = DeliveryType.values.where((d) {
      if (d == DeliveryType.veroCourier) return _veroCourierAvailable;
      return true;
    }).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 64;
        const gap = 8.0;
        final cols = maxW < 340 ? 2 : 3;
        final tileW = ((maxW - gap * (cols - 1)) / cols).clamp(96.0, 200.0);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final d in options)
              SizedBox(width: tileW, child: _courierTile(d)),
          ],
        );
      },
    );
  }

  Future<bool> _foodKitchenAllowsLilongwe(CartModel it) async {
    if (CourierCityHelper.isLilongwe(text: it.location)) return true;
    final mentioned = CourierCityHelper.citiesMentioned(it.location);
    if (mentioned.any((c) => c != CourierServiceCity.lilongwe)) {
      return false;
    }
    if (await CourierCityHelper.merchantIsInLilongwe(it.merchantId)) {
      return true;
    }
    if (await CourierCityHelper.merchantIsInLilongwe(it.restaurantId)) {
      return true;
    }
    return mentioned.isEmpty;
  }

  Future<void> _resolveMerchantCourierCities() async {
    if (_items.isEmpty) {
      if (mounted) setState(() => _merchantsInLilongwe = false);
      return;
    }
    final checks = await Future.wait(_items.map((it) async {
      if (_isFoodCheckout) return _foodKitchenAllowsLilongwe(it);
      if (CourierCityHelper.isLilongwe(text: it.location)) return true;
      if (await CourierCityHelper.merchantIsInLilongwe(it.merchantId)) {
        return true;
      }
      return CourierCityHelper.merchantIsInLilongwe(it.restaurantId);
    }));
    final ok = checks.isNotEmpty && checks.every((v) => v);
    if (!mounted) return;
    setState(() {
      _merchantsInLilongwe = ok;
      _clampDeliveryType();
    });
  }

  @override
  void initState() {
    super.initState();
    _items = List<CartModel>.from(widget.items);
    if (_isFoodCheckout) {
      _deliveryType = DeliveryType.veroCourier;
    }
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (it.maxOrderQty > 0 && it.quantity > it.maxOrderQty) {
        _items[i] = it.copyWith(quantity: it.maxOrderQty);
      }
    }
    for (final it in _items) {
      _qtyCtrls[_qtyKey(it)] =
          TextEditingController(text: '${it.quantity}');
    }
    _prepareCartImages();
    final mem = AddressService.peekDefaultAddress();
    if (mem != null) {
      _defaultAddr = mem;
      _loadingAddr = false;
      _loggedIn = true;
    } else {
      _hydrateAddressFromCache();
    }
    _initAuthAndAddress();
    unawaited(_resolveMerchantCourierCities());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precacheCartImages();
    });
  }

  @override
  void dispose() {
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _setItemQty(int index, int value, {bool showStockToast = true}) {
    if (index < 0 || index >= _items.length) return;
    final it = _items[index];
    final maxQ = it.maxOrderQty;
    if (maxQ <= 0) {
      ToastHelper.showCustomToast(
        context,
        'This item is out of stock',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    var next = value;
    if (next < 1) next = 1;
    if (next > maxQ) {
      if (showStockToast) {
        ToastHelper.showCustomToast(
          context,
          it.isFood ? 'Only $maxQ available for this dish.' : 'Only $maxQ available',
          isSuccess: false,
          errorMessage: '',
        );
      }
      next = maxQ;
    }
    if (it.quantity == next) {
      final ctrl = _qtyCtrls[_qtyKey(it)];
      if (ctrl != null && ctrl.text != '$next') {
        ctrl.value = TextEditingValue(
          text: '$next',
          selection: TextSelection.collapsed(offset: '$next'.length),
        );
      }
      return;
    }
    final updated = it.copyWith(quantity: next);
    final key = _qtyKey(updated);
    setState(() => _items[index] = updated);
    final ctrl = _qtyCtrls[key] ?? _qtyCtrls[_qtyKey(it)];
    if (ctrl != null && ctrl.text != '$next') {
      ctrl.value = TextEditingValue(
        text: '$next',
        selection: TextSelection.collapsed(offset: '$next'.length),
      );
    }
  }

  void _onQtyTyped(int index, String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    final n = int.tryParse(digits);
    if (n == null) return;
    _setItemQty(index, n);
  }

  void _commitQtyTyped(int index) {
    final it = _items[index];
    final ctrl = _qtyCtrls[_qtyKey(it)];
    final digits = (ctrl?.text ?? '').replaceAll(RegExp(r'\D'), '');
    final n = int.tryParse(digits);
    _setItemQty(index, n ?? it.quantity);
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6FA),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: _brandNavy),
      ),
    );
  }

  /// Instant paint from memory/disk — never blocks on the API.
  Future<void> _hydrateAddressFromCache() async {
    final mem = AddressService.peekDefaultAddress();
    if (mem != null) {
      if (!mounted) return;
      setState(() {
        _defaultAddr = mem;
        _loadingAddr = false;
        _loggedIn = true;
      });
      return;
    }
    final disk = await _addrSvc.getCachedDefaultAddress();
    if (!mounted || disk == null) return;
    setState(() {
      _defaultAddr = disk;
      _loadingAddr = false;
      _loggedIn = true;
    });
  }

  void _prepareCartImages() {
    for (final item in _items) {
      final raw = item.image.trim();
      if (raw.isEmpty) continue;
      final lower = raw.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://')) {
        _resolvedHttpUrls[raw] = raw;
        continue;
      }
      try {
        final base64Part = raw.contains(',') ? raw.split(',').last : raw;
        if (base64Part.length > 150) {
          _decodedBytes[raw] = base64Decode(base64Part);
          continue;
        }
      } catch (_) {}
      unawaited(_resolveStorageUrl(raw));
    }
  }

  Future<void> _resolveStorageUrl(String raw) async {
    try {
      final lower = raw.toLowerCase();
      final ref = lower.startsWith('gs://')
          ? FirebaseStorage.instance.refFromURL(raw)
          : FirebaseStorage.instance.ref(raw);
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => _resolvedHttpUrls[raw] = url);
      _precacheUrl(url);
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolvedHttpUrls[raw] = '');
    }
  }

  void _precacheCartImages() {
    for (final url in _resolvedHttpUrls.values) {
      if (url.isNotEmpty) _precacheUrl(url);
    }
  }

  void _precacheUrl(String url) {
    if (!mounted || url.isEmpty) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (64 * dpr).round().clamp(64, 192);
    unawaited(
      precacheImage(
        CachedNetworkImageProvider(
          url,
          maxWidth: cachePx,
          maxHeight: cachePx,
        ),
        context,
      ).catchError((_) {}),
    );
  }

  Future<String?> _readAuthToken() async => AuthHandler.getTokenForApi();

  Future<void> _initAuthAndAddress({bool forceRefresh = false}) async {
    final hadCached = _defaultAddr != null;
    setState(() {
      if (!hadCached || forceRefresh) {
        _loadingAddr = !hadCached;
      }
      if (!hadCached) {
        _loggedIn = false;
      }
    });
    final token = await _readAuthToken();
    if (!mounted) return;
    if (token == null) {
      setState(() {
        _loggedIn = false;
        _loadingAddr = false;
        if (forceRefresh) _defaultAddr = null;
      });
      return;
    }
    try {
      if (!forceRefresh && !hadCached) {
        final cached = await _addrSvc.getCachedDefaultAddress();
        if (mounted && cached != null) {
          setState(() {
            _loggedIn = true;
            _defaultAddr = cached;
            _loadingAddr = false;
          });
        }
      }

      final list = await _addrSvc.getMyAddresses(forceRefresh: forceRefresh);
      Address? def;
      for (final a in list) {
        if (a.isDefault) {
          def = a;
          break;
        }
      }
      def ??= list.isNotEmpty ? list.first : null;
      if (!mounted) return;
      setState(() {
        _loggedIn = true;
        _defaultAddr = def;
        _loadingAddr = false;
        _clampDeliveryType();
      });
      await _applyFoodDropoffPin();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loggedIn = true;
        _loadingAddr = false;
      });
      await _applyFoodDropoffPin();
    }
  }

  Future<void> _applyFoodDropoffPin() async {
    if (!_isFoodCheckout || !mounted) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final lat = sp.getDouble('food_dropoff_lat');
      final lng = sp.getDouble('food_dropoff_lng');
      if (lat == null || lng == null) return;
      final addrText = (sp.getString('food_dropoff_address') ?? '').trim();
      if (!mounted) return;
      final cur = _defaultAddr;
      setState(() {
        _defaultAddr = Address(
          id: cur?.id ?? 'local-food-pin',
          addressType: cur?.addressType ?? AddressType.home,
          city: cur?.city ?? '',
          description:
              addrText.isNotEmpty ? addrText : (cur?.description ?? ''),
          isDefault: true,
          isGoogle: true,
          formattedAddress:
              addrText.isNotEmpty ? addrText : (cur?.formattedAddress ?? ''),
          placeId: cur?.placeId ?? '',
          lat: lat,
          lng: lng,
        );
      });
    } catch (_) {}
  }

  bool get _needsDefaultAddress =>
      _deliveryType != DeliveryType.pickup &&
      _loggedIn &&
      !_loadingAddr &&
      _defaultAddr == null;

  Future<void> _openAddressSetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddressPage()),
    );
    await _initAuthAndAddress(forceRefresh: true);
  }

  Future<void> _onPayBarPressed({required bool canPay}) async {
    if (_paying) return;
    if (_needsDefaultAddress) {
      ToastHelper.showCustomToast(
        context,
        'Set a default delivery address before you pay',
        isSuccess: false,
        errorMessage: '',
      );
      await _openAddressSetup();
      return;
    }
    if (!canPay) return;
    if (!await _latestArrivalsStillAvailable()) return;
    await _startPawaPayPayment();
  }

  /// Re-check latest-arrival stock right before paying (others may have bought).
  /// Network errors do not block payment; the server check after payment still runs.
  Future<bool> _latestArrivalsStillAvailable() async {
    final svc = LatestArrivalsServicess();
    var ok = true;
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      final id = it.latestArrivalId;
      if (id == null) continue;
      int? left;
      try {
        left = await svc.fetchAvailable(id);
      } catch (_) {
        continue;
      }
      if (left == null) continue;
      if (left != it.availableStock && mounted) {
        setState(() => _items[i] = it.copyWith(availableStock: left));
      }
      if (it.quantity > left) {
        ok = false;
        if (mounted) {
          ToastHelper.showCustomToast(
            context,
            left <= 0
                ? '${it.name} is sold out'
                : 'Only $left of ${it.name} left. Lower the quantity.',
            isSuccess: false,
            errorMessage: '',
          );
        }
      }
    }
    return ok;
  }

  Future<bool> _ensureDefaultAddressIfNeeded() async {
    if (_deliveryType == DeliveryType.pickup) return true;
    if (!_loggedIn) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to continue.',
        isSuccess: false,
        errorMessage: 'Auth required',
      );
      return false;
    }
    if (_defaultAddr != null) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delivery address required'),
        content: const Text('You need to set a default address before checkout.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Set address')),
        ],
      ),
    );
    if (go == true) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressPage()));
      await _initAuthAndAddress();
      return _defaultAddr != null;
    }
    return false;
  }

  // ✅ Fast thumbs: disk cache + sized decode (same idea as cart / single checkout)
  Widget _itemImage(String raw, {double size = 64}) {
    final s = raw.trim();
    if (s.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: Colors.grey.shade200,
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }

    final url = _resolvedHttpUrls[s];
    if (url != null && url.isNotEmpty) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cachePx = (size * dpr).round().clamp(64, 192);
      return ResilientCachedNetworkImage(
        url: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: cachePx,
        memCacheHeight: cachePx,
      );
    }

    final bytes = _decodedBytes[s];
    if (bytes != null) {
      final cacheW = (size * MediaQuery.devicePixelRatioOf(context)).round();
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cacheW,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported, color: Colors.grey),
        ),
      );
    }

    // Still resolving Firebase path, or failed.
    if (url == null && !_decodedBytes.containsKey(s)) {
      return Container(
        width: size,
        height: size,
        color: const Color(0xFFF1F1F1),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: _brandOrange),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      color: Colors.grey.shade200,
      child: const Icon(Icons.image_not_supported, color: Colors.grey),
    );
  }

  Future<void> _startPawaPayPayment() async {
    if (_items.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Your cart is empty.',
        isSuccess: false,
        errorMessage: 'Empty cart',
      );
      return;
    }
    if (_hasMixedCart) {
      ToastHelper.showCustomToast(
        context,
        'Food is delivered by Vero Courier only. Checkout food separately from marketplace items.',
        isSuccess: false,
        errorMessage: 'Mixed cart',
      );
      return;
    }
    if (_isFoodCheckout) {
      _deliveryType = DeliveryType.veroCourier;
      if (!_buyerInLilongwe) {
        ToastHelper.showCustomToast(
          context,
          'Vero Courier for food delivery is expanding soon.',
          isSuccess: false,
          errorMessage: 'City not supported',
        );
        return;
      }
      if (!_merchantsInLilongwe) {
        ToastHelper.showCustomToast(
          context,
          'Vero Courier for food delivery is expanding soon.',
          isSuccess: false,
          errorMessage: 'City not supported',
        );
        return;
      }
    } else if (_deliveryType == DeliveryType.veroCourier &&
        !_veroCourierAvailable) {
      ToastHelper.showCustomToast(
        context,
        'Vero Courier is only in Lilongwe, and both you and the shop must be in Lilongwe.',
        isSuccess: false,
        errorMessage: 'City not supported',
      );
      return;
    }
    if (!await _ensureDefaultAddressIfNeeded()) return;
    final agreed = _isFoodCheckout
        ? await showFoodEscrowPayNoticeDialog(context)
        : await showEscrowPayNoticeDialog(context);
    if (!agreed) return;
    if (!mounted) return;

    setState(() => _paying = true);

    try {
      final txRef = 'vero-${DateTime.now().millisecondsSinceEpoch}';
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => InAppPaymentPage(
          txRef: txRef,
          totalAmount: _total,
          rootContext: context,
          clearCartOnSuccess: true,
          cartItemsForMerchantCredit: _items,
          shippingAddress: _deliveryType == DeliveryType.pickup ? null : _defaultAddr,
          deliveryType: _deliveryType,
          onSuccessNavigate: _isFoodCheckout
              ? (root) {
                  Navigator.of(root).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const FoodMyOrdersPage(),
                    ),
                    (route) => route.isFirst,
                  );
                }
              : null,
        ),
      ));
    } on SocketException catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Network error. Please check your internet connection.',
        isSuccess: false,
        errorMessage: e.message,
      );
    } on TimeoutException {
      ToastHelper.showCustomToast(
        context,
        'Connection timeout. Please try again.',
        isSuccess: false,
        errorMessage: 'Request timed out',
      );
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Payment initialization failed',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
      fontSize: bold ? 16 : 14,
      color: bold ? _brandNavy : Colors.grey.shade800,
    );
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 10),
        Text(value,
            style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final foodCityOk = !_isFoodCheckout || _foodCourierCity != null;
    final stockOk = !_items.any(
      (it) => it.maxOrderQty < 1 || it.quantity > it.maxOrderQty,
    );
    final canPay = !_paying &&
        _items.isNotEmpty &&
        !_hasMixedCart &&
        foodCityOk &&
        stockOk &&
        (_deliveryType == DeliveryType.pickup || _defaultAddr != null);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        centerTitle: false,
        titleSpacing: 0,
        title: Text(
          _isFoodCheckout ? 'Food checkout' : 'Checkout',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            letterSpacing: -0.4,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back to cart',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _stepsHeader(),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 18,
                          color: _brandNavy.withValues(alpha: 0.7)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Secure checkout · Airtel Money or TNM Mpamba',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_isFoodCheckout) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _foodCourierCity != null
                          ? const Color(0xFFEEF8F1)
                          : const Color(0xFFFFF3E8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (_foodCourierCity != null
                                ? const Color(0xFF2E7D32)
                                : _brandOrange)
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.delivery_dining_rounded,
                          color: _foodCourierCity != null
                              ? const Color(0xFF2E7D32)
                              : _brandOrange,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _foodCourierCity != null
                                ? 'Vero Courier will deliver this food  in Lilongwe only.'
                                : (!_buyerInLilongwe
                                    ? 'Vero Courier for food delivery is expanding soon.'
                                    : 'This restaurant is outside Lilongwe. Vero Courier for food delivery is expanding soon.'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                              color: _brandNavy,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                _section(
                  title: 'Your items',
                  subtitle: _itemsSectionSubtitle,
                  child: ListView.separated(
                    itemCount: _items.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    separatorBuilder: (_, __) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: Colors.grey.shade200),
                    ),
                    itemBuilder: (_, i) {
                      final it = _items[i];
                      final customerLine = BuyerCommission.allocateLines(
                        _items.map((e) => e.price * e.quantity).toList(),
                      )[i].buyerTotal;
                      final qtyCtrl = _qtyCtrls.putIfAbsent(
                        _qtyKey(it),
                        () => TextEditingController(text: '${it.quantity}'),
                      );
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: _itemImage(it.image, size: 64),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  it.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: _brandNavy,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _mwk(it.quantity <= 0 ? customerLine : customerLine / it.quantity),
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5,
                                  ),
                                ),
                                if (it.maxOrderQty < 99999) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    it.maxOrderQty < 1
                                        ? 'Out of stock'
                                        : 'Only ${it.maxOrderQty} available',
                                    style: TextStyle(
                                      color: it.maxOrderQty < 1
                                          ? Colors.red.shade700
                                          : Colors.grey.shade600,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                                if (it.isFood && it.prepTimeLabel != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        it.prepTimeLabel!,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _qtyBtn(Icons.remove_rounded, () {
                                      _setItemQty(
                                        i,
                                        it.quantity - 1,
                                        showStockToast: false,
                                      );
                                    }),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 64,
                                      child: TextField(
                                        controller: qtyCtrl,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(5),
                                        ],
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                          color: _brandNavy,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 8,
                                          ),
                                          filled: true,
                                          fillColor: const Color(0xFFF4F6FA),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: BorderSide(
                                              color: Colors.black
                                                  .withValues(alpha: 0.08),
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: BorderSide(
                                              color: Colors.black
                                                  .withValues(alpha: 0.08),
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                              color: _brandOrange,
                                              width: 1.4,
                                            ),
                                          ),
                                        ),
                                        onChanged: (v) => _onQtyTyped(i, v),
                                        onEditingComplete: () =>
                                            _commitQtyTyped(i),
                                        onSubmitted: (_) =>
                                            _commitQtyTyped(i),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    _qtyBtn(Icons.add_rounded, () {
                                      _setItemQty(i, it.quantity + 1);
                                    }),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _mwk(customerLine),
                            style: const TextStyle(
                              color: _brandNavy,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (_hasMixedCart) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _brandOrange.withValues(alpha: 0.35)),
                    ),
                    child: const Text(
                      'Food is delivered by Vero Courier only. Remove marketplace items and checkout food separately.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: _brandNavy,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _section(
                  title: 'Courier',
                  subtitle: _isFoodCheckout
                      ? (_foodCourierCity == null
                          ? 'Vero Courier for food delivery is expanding soon'
                          : 'Food is delivered by Vero Courier in Lilongwe only')
                      : (_deliveryType == DeliveryType.pickup
                          ? 'Pickup selected no delivery address needed'
                          : (_veroCourierAvailable
                              ? 'Vero Courier is available for food delivery you and the shop are both in Lilongwe'
                              : 'Choose how you want your order delivered')),
                  child: _courierGrid(),
                ),
                const SizedBox(height: 12),
                _DeliveryAddressCard(
                  loading: _loadingAddr,
                  loggedIn: _loggedIn,
                  address: _defaultAddr,
                  pickupSelected: _deliveryType == DeliveryType.pickup,
                  pickupLocation: 'Pickup at merchant(s)',
                  onManage: _openAddressSetup,
                ),
                const SizedBox(height: 12),
                _section(
                  title: 'Summary',
                  child: Column(
                    children: [
                      _row('Subtotal', _mwk(_total)),
                      const SizedBox(height: 10),
                      _row(
                        'Delivery',
                        _deliveryType == DeliveryType.pickup
                            ? 'Pickup'
                            : _deliveryLabel(_deliveryType),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child:
                            Divider(height: 1, color: Colors.grey.shade200),
                      ),
                      _row('Total', _mwk(_total), bold: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _stickyPayBar(canPay: canPay, needsDefaultAddress: _needsDefaultAddress),
        ],
      ),
    );
  }

  Widget _stickyPayBar({
    required bool canPay,
    required bool needsDefaultAddress,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        needsDefaultAddress ? 10 : 12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (needsDefaultAddress) ...[
            Material(
              color: const Color(0xFFFFF3E8),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _openAddressSetup,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 20,
                        color: _brandOrange.withValues(alpha: 0.95),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Set a default delivery address above, then continue to Pay Now',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                            color: _brandNavy.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_upward_rounded,
                        size: 18,
                        color: _brandOrange.withValues(alpha: 0.9),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _mwk(_total),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _brandNavy,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed:
                      _paying ? null : () => _onPayBarPressed(canPay: canPay),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        (canPay || needsDefaultAddress)
                            ? _brandOrange
                            : Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _paying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          needsDefaultAddress ? 'Set address' : 'Pay Now',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Delivery Address card (same pattern as checkout_page) ─────────
class _DeliveryAddressCard extends StatelessWidget {
  const _DeliveryAddressCard({
    required this.loading,
    required this.loggedIn,
    required this.address,
    required this.onManage,
    required this.pickupSelected,
    this.pickupLocation,
  });

  final bool loading;
  final bool loggedIn;
  final Address? address;
  final VoidCallback onManage;
  final bool pickupSelected;
  final String? pickupLocation;

  @override
  Widget build(BuildContext context) {
    const brandOrange = Color(0xFFFF8A00);
    final needsAttention =
        !pickupSelected && loggedIn && !loading && address == null;

    Widget card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: needsAttention ? const Color(0xFFFFF8F0) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: needsAttention
              ? brandOrange.withValues(alpha: 0.55)
              : Colors.black.withValues(alpha: 0.06),
          width: needsAttention ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Delivery address',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Color(0xFF16284C),
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (!pickupSelected)
                TextButton.icon(
                  onPressed: onManage,
                  style: TextButton.styleFrom(
                    foregroundColor: brandOrange,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                  label: Text(
                    address == null ? 'Set default' : 'Change',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          if (needsAttention) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: brandOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    size: 18,
                    color: brandOrange.withValues(alpha: 0.95),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap Set default to add where we should deliver your order',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: const Color(0xFF16284C).withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (pickupSelected)
            _addrBox(
              Icons.storefront_rounded,
              'Shop pickup',
              (pickupLocation ?? '').trim().isEmpty
                  ? 'Pickup at merchant(s)'
                  : pickupLocation!.trim(),
            )
          else if (loading)
            const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (!loggedIn)
            _addrBox(Icons.lock_outline_rounded, 'Not logged in',
                'Please log in to select address')
          else if (address == null)
            _addrBox(Icons.location_off_outlined, 'No default address',
                'Add an address and mark it as default to continue')
          else
            _addrBox(
              Icons.place_rounded,
              _label(address!.addressType),
              [
                address!.city,
                if (address!.description.isNotEmpty) address!.description,
              ].join(' · '),
            ),
        ],
      ),
    );

    if (needsAttention) {
      card = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onManage,
          borderRadius: BorderRadius.circular(18),
          child: card,
        ),
      );
    }

    return card;
  }

  static Widget _addrBox(IconData icon, String title, String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF16284C)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF16284C),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _label(AddressType t) {
    switch (t) {
      case AddressType.home:
        return 'Home';
      case AddressType.work:
        return 'Office';
      case AddressType.business:
        return 'Business';
      case AddressType.other:
        return 'Other';
    }
  }
}

// ────────────────────── FOOD CHECKOUT (single item, PawaPay → food_orders) ──────────────────────
class FoodCheckoutContext {
  const FoodCheckoutContext({
    required this.merchantId,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.deliveryAddress,
    required this.foodName,
    required this.totalMwk,
    this.deliveryLat,
    this.deliveryLng,
    this.customerNote,
    this.foodImageUrl,
    this.sqlListingId,
    this.firestoreListingId,
  });

  final String merchantId;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final String deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final String foodName;
  final double totalMwk;
  final String? customerNote;
  final String? foodImageUrl;
  final String? sqlListingId;
  final String? firestoreListingId;
}

// ────────────────────── IN-APP PAYMENT PAGE ──────────────────────
class InAppPaymentPage extends StatefulWidget {
  final String txRef;
  final double totalAmount;
  final BuildContext rootContext;
  /// When set, this is a digital product purchase: show product-specific messages and go back to homepage after payment.
  final String? digitalProductName;
  /// When true, clears the cart (backend + local backup) after a successful payment.
  final bool clearCartOnSuccess;
  /// Cart items for marketplace: on success, create orders + escrow hold (merchant paid after confirm / 5d).
  final List<CartModel>? cartItemsForMerchantCredit;
  /// Shipping address used during checkout (null when pickup).
  final Address? shippingAddress;
  /// Delivery type chosen during checkout (needed for pending orders, etc.).
  final DeliveryType deliveryType;
  /// When true, on payment success only close this page (don't navigate to Orders).
  /// Use for flows where the caller handles post-payment UI.
  final bool popOnlyOnSuccess;

  /// When set, runs after a successful payment. Skips the default
  /// navigation to [OrdersPage]. Use for accommodation: return guest to stays list.
  final void Function(BuildContext rootContext)? onSuccessNavigate;

  /// Optional Firestore escrow hold for the accommodation host (wallet / payouts).
  final AccommodationEscrowParams? accommodationEscrow;

  /// Host/seller price when [totalAmount] includes buyer commission.
  /// Escrow credits this amount to the merchant, not the buyer total.
  final double? providerAmountMwk;

  /// Single-item food: after verified payment, writes `food_orders` for the merchant dashboard.
  final FoodCheckoutContext? foodCheckout;

  const InAppPaymentPage({
    super.key,
    required this.txRef,
    required this.totalAmount,
    required this.rootContext,
    this.digitalProductName,
    this.clearCartOnSuccess = false,
    this.cartItemsForMerchantCredit,
    this.shippingAddress,
    this.deliveryType = DeliveryType.speed,
    this.popOnlyOnSuccess = false,
    this.onSuccessNavigate,
    this.accommodationEscrow,
    this.foodCheckout,
    this.providerAmountMwk,
  });

  @override
  State<InAppPaymentPage> createState() => _InAppPaymentPageState();
}

class _InAppPaymentPageState extends State<InAppPaymentPage> {
  Timer? _pollTimer;
  bool _resultHandled = false;
  final order_svc.OrderService _orderService = order_svc.OrderService();
  final TextEditingController _momoPhone = TextEditingController();
  String _momoOperator = PawaPayPayment.airtelOperatorId;
  bool _momoBusy = false;
  bool _momoWaiting = false;
  String _momoMessage = '';

  @override
  void initState() {
    super.initState();
    _prefillMomoPhone();
  }

  Future<void> _prefillMomoPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = (prefs.getString('phone') ??
            prefs.getString('user_phone') ??
            FirebaseAuth.instance.currentUser?.phoneNumber ??
            '')
        .trim();
    if (!mounted || phone.isEmpty || _momoPhone.text.isNotEmpty) return;
    final local = PawaPayPayment.localPhone(phone);
    _momoPhone.text = local;
    final guessed = PawaPayPayment.operatorForPhone(local);
    if (guessed != null) setState(() => _momoOperator = guessed);
  }

  Future<void> _startPawaPayDeposit() async {
    if (_momoBusy || _resultHandled) return;
    setState(() {
      _momoBusy = true;
      _momoWaiting = false;
      _momoMessage = '';
    });
    try {
      final depositId = await PawaPayPayment.createDeposit(
        amountMwk: widget.totalAmount.round(),
        phone: _momoPhone.text.trim(),
        operatorId: _momoOperator,
        reference: widget.txRef,
      );
      if (!mounted) return;
      setState(() => _momoWaiting = true);
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        try {
          final status = await PawaPayPayment.readStatus(depositId);
          final state = (status['status'] ?? '').toString();
          if (state == 'completed') {
            _handlePaymentSuccess();
          } else if (state == 'failed') {
            _pollTimer?.cancel();
            if (!mounted) return;
            setState(() {
              _momoBusy = false;
              _momoWaiting = false;
              _momoMessage = PawaPayPayment.explainFailure(
                (status['failure'] ?? '').toString(),
              );
            });
          }
        } catch (_) {}
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _momoBusy = false;
        _momoWaiting = false;
        _momoMessage = PawaPayPayment.readableError(e);
      });
    }
  }


  /// Backend orders + Firestore escrow (merchant wallet credited after buyer confirms or 7 days).
  Future<void> _createConfirmedOrdersAndEscrow(List<CartModel> items) async {
    unawaited(_recordLatestArrivalPurchases(items));
    try {
      final addressForOrder =
          widget.deliveryType == DeliveryType.pickup ? null : widget.shippingAddress;
      final refs = await _orderService.createOrdersFromCartWithRefs(
        cartItems: items,
        address: addressForOrder,
        status: OrderStatus.confirmed,
        deliveryMethod: _deliveryTypeLabel(widget.deliveryType),
      );
      await OrderEscrowService.createHoldsForOrders(
        txRef: widget.txRef,
        refs: refs,
      );
    } catch (e) {
      debugPrint('[InAppPaymentPage] Failed to create orders / escrow: $e');
      final message = (e is order_svc.AuthRequiredException || e is order_svc.FriendlyApiException)
          ? e.toString()
          : 'We couldn’t finalize your order. Please contact support.';
      if (mounted && widget.rootContext.mounted) {
        ToastHelper.showCustomToast(
          widget.rootContext,
          'Order finalize failed',
          isSuccess: false,
          errorMessage: message,
        );
      }
    }
  }


  /// Paid latest arrivals: reduce the merchant's posted quantity.
  Future<void> _recordLatestArrivalPurchases(List<CartModel> items) async {
    final svc = LatestArrivalsServicess();
    for (final it in items) {
      final id = it.latestArrivalId;
      if (id == null || it.quantity <= 0) continue;
      try {
        await svc.recordPurchase(id, it.quantity);
      } catch (e) {
        debugPrint('[InAppPaymentPage] Latest arrival stock update failed: $e');
      }
    }
  }

  Future<void> _createBackendOrders(OrderStatus status) async {
    try {
      final raw = widget.cartItemsForMerchantCredit;
      if (raw == null || raw.isEmpty) return;
      final items = raw.where((e) => !e.isFood).toList();
      if (items.isEmpty) return;

      // For pickup we don't send an addressId (backend receives 0).
      final addressForOrder =
          widget.deliveryType == DeliveryType.pickup ? null : widget.shippingAddress;

      await _orderService.createOrdersFromCart(
        cartItems: items,
        address: addressForOrder,
        status: status,
        deliveryMethod: _deliveryTypeLabel(widget.deliveryType),
      );
    } catch (e) {
      debugPrint('[InAppPaymentPage] Failed to create backend orders: $e');
      final message = (e is order_svc.AuthRequiredException || e is order_svc.FriendlyApiException)
              ? e.toString()
              : 'We couldn’t create your order. Please try again.';
      if (mounted && widget.rootContext.mounted) {
        ToastHelper.showCustomToast(
          widget.rootContext,
          'Order creation failed',
          isSuccess: false,
          errorMessage: message,
        );
      }
    }
  }

  String _deliveryTypeLabel(DeliveryType type) {
    switch (type) {
      case DeliveryType.speed:
        return 'Speed';
      case DeliveryType.cts:
        return 'CTS';
      case DeliveryType.ankolo:
        return 'Ankolo';
      case DeliveryType.smart:
        return 'Smart';
      case DeliveryType.veroCourier:
        return 'Vero Courier';
      case DeliveryType.pickup:
        return 'Pickup';
    }
  }

  Future<void> _persistFoodOrderAfterPayment({
    List<CartModel> cartFoodItems = const [],
  }) async {
    final fc = widget.foodCheckout;
    final foodLines = cartFoodItems.where((e) => e.isFood).toList();
    if (fc == null && foodLines.isEmpty) return;

    try {
      final ref = FirebaseFirestore.instance.collection('food_orders').doc();
      final orderNumber = generateFoodOrderNumber();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final prefs = await SharedPreferences.getInstance();
      final addr = widget.shippingAddress;

      final lineItems = <FoodOrderLineItem>[];
      String merchantId = '';
      String restaurantId = '';
      String merchantName = 'Kitchen';
      String customerName = '';
      String customerPhone = '';
      String customerEmail = '';
      String deliveryAddress = '';
      double? deliveryLat;
      double? deliveryLng;
      String? customerNote;

      if (fc != null) {
        merchantId = fc.merchantId;
        customerName = fc.customerName;
        customerPhone = fc.customerPhone;
        customerEmail = fc.customerEmail;
        deliveryAddress = fc.deliveryAddress;
        deliveryLat = fc.deliveryLat;
        deliveryLng = fc.deliveryLng;
        customerNote = fc.customerNote;
        lineItems.add(FoodOrderLineItem(
          menuItemId: fc.firestoreListingId ?? fc.sqlListingId ?? '',
          name: fc.foodName,
          unitPriceMwk: fc.totalMwk,
          quantity: 1,
          notes: fc.customerNote,
          imageUrl: fc.foodImageUrl,
        ));
      } else {
        merchantId = foodLines.first.merchantId;
        restaurantId = foodLines.first.restaurantId?.trim() ?? '';
        merchantName = foodLines.first.merchantName;
        customerName = (prefs.getString('user_full_name') ??
                prefs.getString('name') ??
                '')
            .trim();
        customerPhone = sanitizedPhoneOrEmpty(
          prefs.getString('user_phone') ??
              prefs.getString('phone') ??
              FirebaseAuth.instance.currentUser?.phoneNumber,
        );
        customerEmail = (prefs.getString('email') ??
                FirebaseAuth.instance.currentUser?.email ??
                '')
            .trim();
        deliveryAddress = [
          addr?.description,
          addr?.city,
        ].where((e) => e != null && e.trim().isNotEmpty).join(', ');
        final pinAddr = (prefs.getString('food_dropoff_address') ?? '').trim();
        if (deliveryAddress.trim().isEmpty && pinAddr.isNotEmpty) {
          deliveryAddress = pinAddr;
        }
        deliveryLat = prefs.getDouble('food_dropoff_lat') ?? addr?.lat;
        deliveryLng = prefs.getDouble('food_dropoff_lng') ?? addr?.lng;
        for (final line in foodLines) {
          lineItems.add(FoodOrderLineItem(
            menuItemId: (line.listingDocId?.trim().isNotEmpty == true)
                ? line.listingDocId!.trim()
                : '${line.item}',
            name: line.name,
            unitPriceMwk: line.price,
            quantity: line.quantity,
            variant: line.variant,
            notes: line.notes ?? line.comment,
            addOns: line.addOns,
            imageUrl: line.image.trim().isEmpty ? null : line.image.trim(),
          ));
        }
      }

      String? coverImageUrl;
      for (final line in lineItems) {
        final img = line.imageUrl?.trim() ?? '';
        if (img.isNotEmpty) {
          coverImageUrl = img;
          break;
        }
      }
      if (coverImageUrl == null && fc?.foodImageUrl?.trim().isNotEmpty == true) {
        coverImageUrl = fc!.foodImageUrl!.trim();
      }

      final subtotalMwk =
          lineItems.fold<double>(0, (s, e) => s + e.lineTotalMwk);
      const deliveryFeeMwk = 0.0;
      final serviceFeeMwk = BuyerCommission.quote(subtotalMwk).commission;
      final totalMwk = subtotalMwk + deliveryFeeMwk + serviceFeeMwk;

      String pickupAddress = '';
      double? pickupLat;
      double? pickupLng;
      try {
        final restSvc = RestaurantService();
        final rest = restaurantId.trim().isNotEmpty
            ? await restSvc.fetchRestaurantById(restaurantId)
            : await restSvc.fetchRestaurantByOwnerUid(merchantId);
        pickupAddress = (rest?.address ?? '').trim();
        pickupLat = rest?.latitude;
        pickupLng = rest?.longitude;
      } catch (e) {
        debugPrint('[InAppPaymentPage] restaurant pickup lookup failed: $e');
      }

      final order = FoodOrder(
        id: ref.id,
        orderNumber: orderNumber,
        restaurantId: restaurantId,
        merchantId: merchantId,
        customerUid: uid,
        customerName: customerName,
        customerPhone: customerPhone,
        customerEmail: customerEmail,
        deliveryAddress: deliveryAddress,
        deliveryLat: deliveryLat,
        deliveryLng: deliveryLng,
        lineItems: lineItems,
        subtotalMwk: subtotalMwk,
        deliveryFeeMwk: deliveryFeeMwk,
        serviceFeeMwk: serviceFeeMwk,
        totalMwk: totalMwk,
        status: 'pending',
        paymentTxRef: widget.txRef,
        paymentStatus: 'paid',
        restaurantName: merchantName,
        deliveryMethod: FoodCourierDispatch.methodLabel,
        courierProvider: FoodCourierDispatch.provider,
        pickupAddress: pickupAddress,
        coverImageUrl: coverImageUrl,
      );

      await ref.set({
        ...order.toJson(),
        'orderId': ref.id,
        'orderNumber': orderNumber,
        'customerId': uid,
        // Legacy dashboard fields until the merchant UI is updated.
        'totalAmount': totalMwk,
        'items': lineItems
            .map((e) => {
                  'name': e.name,
                  'price': e.unitPriceMwk,
                  'quantity': e.quantity,
                  if (e.imageUrl != null && e.imageUrl!.trim().isNotEmpty)
                    'imageUrl': e.imageUrl!.trim(),
                  if (e.variant != null) 'variant': e.variant,
                  if (e.notes != null) 'notes': e.notes,
                  if (e.addOns.isNotEmpty) 'addOns': e.addOns,
                })
            .toList(),
        if (customerNote != null && customerNote.trim().isNotEmpty)
          'customerNote': customerNote.trim(),
        if (pickupLat != null) 'pickupLat': pickupLat,
        if (pickupLng != null) 'pickupLng': pickupLng,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final summaryName = lineItems.length == 1
          ? lineItems.first.name
          : '${lineItems.length} dishes';
      await OrderEscrowService.createHoldForFoodOrder(
        orderId: ref.id,
        txRef: widget.txRef,
        merchantUid: merchantId,
        merchantName: merchantName,
        foodName: summaryName,
        grossAmountMwk: subtotalMwk,
        orderNumber: orderNumber,
      );

      final itemsSummary = lineItems.length == 1
          ? lineItems.first.name
          : lineItems
              .take(3)
              .map((e) => e.quantity > 1 ? '${e.quantity}x ${e.name}' : e.name)
              .join(', ');

      await OrderPartyNotificationService.publishNewFoodOrderToMerchant(
        merchantUid: merchantId,
        customerName: customerName,
        orderNumber: orderNumber,
        orderId: ref.id,
        itemsSummary: itemsSummary,
        totalMwk: totalMwk,
      );
      if (uid.isNotEmpty) {
        await OrderPartyNotificationService.publishFoodOrderPlacedToBuyer(
          buyerUid: uid,
          orderNumber: orderNumber,
          orderId: ref.id,
          restaurantName: merchantName,
          itemsSummary: itemsSummary,
        );
      }
    } catch (e) {
      debugPrint('[InAppPaymentPage] food_orders write failed: $e');
      if (widget.rootContext.mounted) {
        ToastHelper.showCustomToast(
          widget.rootContext,
          'Payment OK but order sync failed. Contact support with ref ${widget.txRef}.',
          isSuccess: false,
          errorMessage: 'Sync failed',
        );
      }
    }
  }

  void _handlePaymentSuccess() {
    if (_resultHandled) return;
    _resultHandled = true;
    _pollTimer?.cancel();

    final shouldClearCart = widget.clearCartOnSuccess;
    final clearFuture = shouldClearCart
        ? () async {
            try {
              final cart = CartServiceProvider.getInstance();
              await cart.clearCart();
            } catch (e) {
              debugPrint('[InAppPaymentPage] Failed to clear cart: $e');
            }
          }()
        : Future<void>.value();

    // Non-cart paths still fire-and-forget; cart path awaits below.

    final food = widget.foodCheckout;
    final cartItems = widget.cartItemsForMerchantCredit ?? const <CartModel>[];
    final foodItems = cartItems.where((e) => e.isFood).toList();
    final marketItems = cartItems.where((e) => !e.isFood).toList();
    final esc = widget.accommodationEscrow;

    // Earn a Vero spin after successful marketplace / food / stay payment.
    final spinSource = (food != null || foodItems.isNotEmpty)
        ? VeroRewardsService.sourceFood
        : (marketItems.isNotEmpty ||
                (widget.cartItemsForMerchantCredit?.isNotEmpty == true))
            ? VeroRewardsService.sourceMarketplace
            : (esc != null)
                ? VeroRewardsService.sourceAccommodation
                : null;
    if (spinSource != null) {
      unawaited(
        VeroSpinRewardPrompt.grantAndPrompt(
          source: spinSource,
          reference: widget.txRef,
        ),
      );
    }

    if (food != null || foodItems.isNotEmpty) {
      unawaited(_persistFoodOrderAfterPayment(cartFoodItems: foodItems));
    }

    if (marketItems.isNotEmpty) {
      unawaited(_createConfirmedOrdersAndEscrow(marketItems));
    } else if (food == null && foodItems.isEmpty) {
      final items = widget.cartItemsForMerchantCredit;
      if (items != null && items.isNotEmpty) {
        unawaited(_createConfirmedOrdersAndEscrow(items));
      }
    }

    final isFoodCartCheckout = foodItems.isNotEmpty && food == null;

    if (food != null && marketItems.isEmpty) {
      ToastHelper.showCustomToast(
        widget.rootContext,
        'Payment successful — the kitchen has your order.',
        isSuccess: true,
        errorMessage: '',
      );
      if (mounted) Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.rootContext.mounted) {
          Navigator.of(widget.rootContext).pop();
          Navigator.of(widget.rootContext).push(
            MaterialPageRoute(builder: (_) => const FoodMyOrdersPage()),
          );
        }
      });
      return;
    }
    if (esc != null) {
      unawaited(OrderEscrowService.createHoldForAccommodationBooking(
        txRef: widget.txRef,
        grossAmountMwk: widget.providerAmountMwk ?? widget.totalAmount,
        params: esc,
      ));
    }
    final isDigital = widget.digitalProductName != null && widget.digitalProductName!.isNotEmpty;
    final productName = widget.digitalProductName ?? 'your order';

    // Persist digital order / platform fee credit when caller provided a hook.
    if (isDigital && widget.onSuccessNavigate != null) {
      try {
        widget.onSuccessNavigate!(widget.rootContext);
      } catch (e) {
        debugPrint('[InAppPaymentPage] digital onSuccessNavigate failed: $e');
      }
    }

    ToastHelper.showCustomToast(
      widget.rootContext,
      isDigital
          ? 'Payment successful!'
          : isFoodCartCheckout
              ? 'Payment successful — the kitchen has your order.'
              : 'Payment Successful!',
      isSuccess: true,
      errorMessage: '',
    );

    if (isDigital) {
      // Digital purchase: thank-you message (email not sent from app)
      final message =
          'Thank you for purchasing $productName on Vero. Contact support if you need instructions.';
      if (mounted) {
        Navigator.of(context).pop(); // close webview
        if (!widget.rootContext.mounted) return;
        showDialog(
          context: widget.rootContext,
          builder: (ctx) => AlertDialog(
            title: const Text('Purchase successful'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(widget.rootContext).pop(); // back to homepage (pops DigitalProductDetailPage)
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } else if (widget.onSuccessNavigate != null) {
      if (mounted) {
        Navigator.of(context).pop(); // close webview
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (widget.rootContext.mounted) {
            widget.onSuccessNavigate!(widget.rootContext);
          }
        });
      }
    } else if (widget.popOnlyOnSuccess) {
      if (mounted) Navigator.of(context).pop();
    } else {
      // Cart checkout: finish clearing before leaving so the cart isn't "stuck".
      unawaited(() async {
        await clearFuture;
        if (!mounted) return;
        Navigator.of(context).pop(); // close webview
        if (!widget.rootContext.mounted) return;
        Navigator.of(widget.rootContext).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OrdersPage()),
          (route) => route.isFirst,
        );
      }());
    }
  }

  void _handlePaymentFailure() {
    if (_resultHandled) return;
    _resultHandled = true;
    _pollTimer?.cancel();
    final isDigital = widget.digitalProductName != null && widget.digitalProductName!.isNotEmpty;

    // For cart checkout flows, record a pending order when payment was not completed.
    // This lets the backend know about the intent even if the user abandons payment.
    unawaited(_createBackendOrders(OrderStatus.pending));

    if (isDigital) {
      // Digital purchase: failure message (email not sent from app)
      final message =
          'Payment was not successful. Contact support if you need help or a refund.';
      ToastHelper.showCustomToast(
        widget.rootContext,
        'Payment failed',
        isSuccess: false,
        errorMessage: 'Payment was not completed',
      );
      if (mounted) {
        Navigator.of(context).pop(); // close webview
        if (!widget.rootContext.mounted) return;
        showDialog(
          context: widget.rootContext,
          builder: (ctx) => AlertDialog(
            title: const Text('Payment failed'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(widget.rootContext).pop(); // back to homepage
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } else {
      ToastHelper.showCustomToast(
        widget.rootContext,
        'Payment Failed or Cancelled',
        isSuccess: false,
        errorMessage: 'Payment was not completed',
      );
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _momoPhone.dispose();
    super.dispose();
  }

  Future<void> _onBackPressed() async {
    final isCartCheckout = widget.cartItemsForMerchantCredit != null &&
        widget.cartItemsForMerchantCredit!.isNotEmpty;
    final goBack = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8A00).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.payments_rounded,
                    color: Color(0xFFFF8A00),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Cancel payment?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    letterSpacing: -0.3,
                    color: Color(0xFF16284C),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isCartCheckout
                      ? 'You can complete payment later from your cart.'
                      : 'You can come back and pay when you are ready.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF8A5A32),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A00),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    child: const Text('Stay and pay'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF16284C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    child: Text(
                      isCartCheckout ? 'Back to checkout' : 'Leave payment',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    if (goBack == true && mounted) Navigator.of(context).pop();
  }

  Widget _pawaPayBody() {
    return PawaPayCheckoutView(
      amountMwk: widget.totalAmount.round(),
      phoneController: _momoPhone,
      operatorId: _momoOperator,
      onOperatorChanged: (value) => setState(() => _momoOperator = value),
      onSubmit: _startPawaPayDeposit,
      busy: _momoBusy,
      waiting: _momoWaiting,
      message: _momoMessage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBackPressed();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF8F2),
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: const Color(0xFFFFF8F2),
          foregroundColor: const Color(0xFF16284C),
          centerTitle: false,
          titleSpacing: 8,
          title: const Text(
            'Payment',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: -0.2,
              color: Color(0xFF16284C),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: _onBackPressed,
            tooltip: 'Back to checkout',
          ),
        ),
        body: _pawaPayBody(),
      ),
    );
  }
}

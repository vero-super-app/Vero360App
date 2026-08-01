import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GeneralModels/address_model.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';
import 'package:vero360_app/GernalServices/notification_service.dart';
import 'package:vero360_app/config/api_config.dart';


/// Thrown when user must login again (safe to show to user)
class AuthRequiredException implements Exception {
  final String message;
  AuthRequiredException([this.message = 'Please sign in to continue.']);
  @override
  String toString() => message;
}

/// Thrown for any API/network issue, with a user-friendly message only.
/// (No endpoints, no status codes, no raw response bodies)
/// One backend order created from a single cart line (used for escrow / payouts).
class CreatedOrderRef {
  final String orderId;
  final String orderNumber;
  final CartModel item;

  const CreatedOrderRef({
    required this.orderId,
    required this.orderNumber,
    required this.item,
  });
}

class FriendlyApiException implements Exception {
  final String message;

  /// For internal logging only (do NOT show to user)
  final String? debugMessage;
  final int? statusCode;

  FriendlyApiException(
    this.message, {
    this.debugMessage,
    this.statusCode,
  });

  @override
  String toString() => message;
}

class OrderService {
  static const String _orderStatusCacheKey = 'order_status_cache_v1';
  static const String _orderStatusInitializedKey = 'order_status_cache_initialized_v1';
  static const String _orderNotifWindowStartKey = 'order_notif_window_start_v1';
  static const String _orderNotifWindowCountKey = 'order_notif_window_count_v1';
  static const int _orderNotifWindowSeconds = 45;

  /* --------------------- infra helpers --------------------- */

  /// Use AuthHandler so we get a fresh Firebase token (auto-refreshes when expired)
  /// or the backend JWT from SharedPreferences. Same source as cart, checkout, etc.
  Future<String> _token() async {
    final token = await AuthHandler.getTokenForApi();
    if (token != null && token.trim().isNotEmpty) return token.trim();
    throw AuthRequiredException('Please sign in to continue.');
  }

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final decoded = jsonDecode(payload);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isMerchant() async {
    // 1) Prefer explicit flags saved during login
    final prefs = await SharedPreferences.getInstance();
    final explicit = (prefs.getBool('is_merchant') ?? prefs.getBool('merchant')) == true;
    if (explicit) return true;

    final roleStr = (prefs.getString('role') ?? prefs.getString('userRole') ?? '').toLowerCase();
    if (roleStr.contains('merchant')) return true;

    // 2) Fallback: inspect JWT claims
    try {
      final t = await _token();
      final p = _decodeJwtPayload(t);
      if (p != null) {
        if (p['isMerchant'] == true) return true;

        final role = (p['role'] ?? '').toString().toLowerCase();
        if (role.contains('merchant')) return true;

        final roles = p['roles'];
        if (roles is List && roles.map((e) => '$e'.toLowerCase()).contains('merchant')) return true;

        final scope = (p['scope'] ?? '').toString().toLowerCase();
        if (scope.contains('merchant')) return true;

        final perms = p['permissions'];
        if (perms is List && perms.map((e) => '$e'.toLowerCase()).contains('merchant')) return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Map<String, String>> _headers() async => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await _token()}',
      };

  /// Picks the first non-empty string among common API key spellings (avoids escrow / order id mismatch).
  String _firstStringFromMap(Map<dynamic, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (!m.containsKey(k) || m[k] == null) continue;
      final s = m[k].toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _statusLabel(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  Future<bool> _canSendOrderNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('pref_notifications_enabled') ?? true;
    final ordersEnabled = prefs.getBool('pref_notifications_orders') ?? true;
    return enabled && ordersEnabled;
  }

  Future<void> _notifyOrderActivity({
    required String orderId,
    required String orderNumber,
    required OrderStatus status,
    required bool changed,
    bool isIncomingForMerchant = false,
    bool orderMarkedShippedByMerchant = false,
    String? customerName,
    String? itemName,
  }) async {
    if (!await _canSendOrderNotifications()) return;

    final formattedOrderNumber = _formatOrderNumber(orderNumber);
    final item = itemName?.trim() ?? '';
    final itemPrefix = item.isEmpty ? '' : '$item - ';
    final itemSeg = item.isEmpty ? '' : ' — $item';
    final orderSeg = formattedOrderNumber.isEmpty
        ? 'Your order'
        : 'Your order $formattedOrderNumber';
    final label = _statusLabel(status);
    final who = (customerName ?? '').trim();
    final customerSuffix = who.isEmpty ? '' : ' from $who';
    final title = switch (status) {
      OrderStatus.pending => 'Order placed',
      OrderStatus.confirmed => 'Order confirmed',
      OrderStatus.delivered when orderMarkedShippedByMerchant => 'Parcel sent',
      OrderStatus.delivered when isIncomingForMerchant => 'Order delivered',
      OrderStatus.delivered => 'Your order has shipped',
      OrderStatus.cancelled => 'Order cancelled',
    };
    final body = switch (status) {
      OrderStatus.pending => isIncomingForMerchant
          ? (formattedOrderNumber.isEmpty
              ? 'You received a new order${who.isEmpty ? ' from a customer' : customerSuffix}.'
              : 'New order received: $itemPrefix$formattedOrderNumber$customerSuffix.')
          : (formattedOrderNumber.isEmpty
              ? 'We received your order and it is pending confirmation.'
              : 'Order $itemPrefix$formattedOrderNumber has been placed and is pending confirmation.'),
      OrderStatus.confirmed => formattedOrderNumber.isEmpty
          ? 'Great news! Your order has been confirmed.'
          : 'Great news! Order $itemPrefix$formattedOrderNumber has been confirmed.',
      OrderStatus.delivered when orderMarkedShippedByMerchant =>
        formattedOrderNumber.isEmpty
            ? 'The parcel is on its way. The buyer can track it in Delivered orders.'
            : '$orderSeg$itemSeg has been shipped. The buyer can track progress in Delivered orders.',
      OrderStatus.delivered when isIncomingForMerchant =>
        formattedOrderNumber.isEmpty
            ? 'Waiting for the buyer to confirm receipt to release your payout.'
            : '$orderSeg$itemSeg was delivered. The buyer can confirm receipt to release funds to your wallet.',
      OrderStatus.delivered => formattedOrderNumber.isEmpty
          ? 'Your order has been shipped. Check progress in Delivered orders.'
          : '$orderSeg$itemSeg has been shipped. Check progress in Delivered orders.',
      OrderStatus.cancelled => formattedOrderNumber.isEmpty
          ? 'Your order was cancelled.'
          : 'Order $itemPrefix$formattedOrderNumber was cancelled.',
    };

    final grouped = await _buildGroupedOrderNotificationText(currentStatus: label);

    final payload = jsonEncode({
      'type': 'order_update',
      'orderId': orderId,
      'orderNumber': formattedOrderNumber,
      'status': orderStatusToApi(status),
      NotificationStore.kPayloadBadgeRoute: NotificationStore.badgeRouteForOrderStatus(
        status,
        isMerchant: isIncomingForMerchant,
      ),
    });

    await NotificationService.instance.showManualNotification(
      title: grouped.$1 ?? title,
      body: grouped.$2 ?? body,
      payload: payload,
    );
  }

  String _formatOrderNumber(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return '';
    if (clean.toLowerCase().startsWith('vero')) return clean;
    return 'Vero$clean';
  }

  Future<(String orderNumber, String itemName)> _resolveOrderMeta(String orderId) async {
    final cleanId = orderId.trim();
    if (cleanId.isEmpty) return ('', '');
    try {
      final orders = await getMyOrders();
      for (final o in orders) {
        if (o.id == cleanId) {
          return (o.orderNumber.trim(), o.itemName.trim());
        }
      }
    } catch (_) {
      // Keep notification flow alive even when lookup fails.
    }
    return ('', '');
  }

  Future<(String?, String?)> _buildGroupedOrderNotificationText({
    required String currentStatus,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final startRaw = prefs.getInt(_orderNotifWindowStartKey);
    final countRaw = prefs.getInt(_orderNotifWindowCountKey) ?? 0;

    final inWindow = startRaw != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(startRaw)).inSeconds <=
            _orderNotifWindowSeconds;

    if (!inWindow) {
      await prefs.setInt(_orderNotifWindowStartKey, now.millisecondsSinceEpoch);
      await prefs.setInt(_orderNotifWindowCountKey, 1);
      return (null, null);
    }

    final nextCount = countRaw + 1;
    await prefs.setInt(_orderNotifWindowCountKey, nextCount);
    if (nextCount < 3) return (null, null);

    return (
      'Order activity update',
      'You have $nextCount recent order updates. Latest: $currentStatus.',
    );
  }

  Future<void> _syncOrderStatusNotifications(
    List<OrderItem> orders, {
    Set<String> incomingMerchantOrderIds = const <String>{},
  }) async {
    if (orders.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final initialized = prefs.getBool(_orderStatusInitializedKey) ?? false;

    Map<String, String> cache = {};
    try {
      final raw = prefs.getString(_orderStatusCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          cache = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    } catch (_) {}

    final nextCache = <String, String>{...cache};
    if (!initialized) {
      for (final o in orders) {
        nextCache[o.id] = orderStatusToApi(o.status);
      }
      await prefs.setString(_orderStatusCacheKey, jsonEncode(nextCache));
      await prefs.setBool(_orderStatusInitializedKey, true);
      return;
    }

    for (final o in orders) {
      final current = orderStatusToApi(o.status);
      final previous = cache[o.id];
      final changed = previous != null && previous != current;
      final firstSeen = previous == null;

      if (changed || firstSeen) {
        await _notifyOrderActivity(
          orderId: o.id,
          orderNumber: o.orderNumber,
          status: o.status,
          changed: changed,
          isIncomingForMerchant: incomingMerchantOrderIds.contains(o.id),
          orderMarkedShippedByMerchant: false,
          customerName: o.customerName,
          itemName: o.itemName,
        );
      }
      nextCache[o.id] = current;
    }

    await prefs.setString(_orderStatusCacheKey, jsonEncode(nextCache));
  }

  Future<void> _upsertOrderStatusCache({
    required String orderId,
    required OrderStatus status,
  }) async {
    final cleanId = orderId.trim();
    if (cleanId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    Map<String, String> cache = {};
    try {
      final raw = prefs.getString(_orderStatusCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          cache = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    } catch (_) {}

    cache[cleanId] = orderStatusToApi(status);
    await prefs.setString(_orderStatusCacheKey, jsonEncode(cache));
  }

  String _friendlyMessageForStatus(int code, {required String action}) {
    if (code == 401 || code == 403) return 'Your session has expired. Please sign in again.';
    if (code == 404) return 'We couldn’t find what you requested.';
    if (code == 408) return 'Request timed out. Please try again.';
    if (code == 409) return 'This request couldn’t be completed due to a conflict. Please refresh and try again.';
    if (code == 422 || code == 400) return 'We couldn’t $action. Please check your details and try again.';
    if (code >= 500) return 'We couldn’t $action right now. Please try again shortly.';
    return 'We couldn’t $action. Please try again.';
  }

  /// Parses API error message from JSON body (e.g. {"message":"Selected user is not a merchant"}).
  String? _messageFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final msg = decoded['message']?.toString();
        if (msg != null && msg.trim().isNotEmpty) return msg.trim();
      }
    } catch (_) {}
    return null;
  }

  Never _bad(http.Response r, {required String action, Object? error, StackTrace? st}) {
    // Always log technical details internally only
    dev.log(
      '[OrderService] HTTP error',
      name: 'OrderService',
      error: error ?? {'status': r.statusCode, 'body': _safeBodyForLogs(r.body)},
      stackTrace: st,
    );

    if (r.statusCode == 401) {
      throw AuthRequiredException('Your session has expired. Please sign in again.');
    }

    // 403 = Forbidden: show backend message when present (e.g. "Not a merchant", "Forbidden")
    if (r.statusCode == 403) {
      final message = _messageFromBody(r.body);
      if (message != null && message.isNotEmpty) {
        throw FriendlyApiException(
          message,
          statusCode: 403,
          debugMessage: 'HTTP 403 (business)',
        );
      }
      throw AuthRequiredException('Your session has expired. Please sign in again.');
    }

    throw FriendlyApiException(
      _friendlyMessageForStatus(r.statusCode, action: action),
      statusCode: r.statusCode,
      debugMessage: 'HTTP ${r.statusCode} (hidden)',
    );
  }

  String _safeBodyForLogs(String body) {
    // Avoid logging massive payloads
    if (body.length <= 1200) return body;
    return '${body.substring(0, 1200)}…(truncated)';
  }

  FriendlyApiException _networkFriendly(Object e, {StackTrace? st, required String action}) {
    // Internal log only
    dev.log('[OrderService] Network/Client error', name: 'OrderService', error: e, stackTrace: st);

    if (e is TimeoutException) {
      return FriendlyApiException('Request timed out. Please try again.', debugMessage: 'Timeout', statusCode: 408);
    }
    if (e is SocketException) {
      return FriendlyApiException('No internet connection. Please check your network and try again.', debugMessage: 'SocketException');
    }
    if (e is http.ClientException) {
      return FriendlyApiException('We couldn’t reach the server. Please try again.', debugMessage: 'ClientException');
    }
    return FriendlyApiException('We couldn’t $action. Please try again.', debugMessage: 'Unknown error: $e');
  }

  Future<http.Response> _retry(
    Future<http.Response> Function() run, {
    int retries = 2,
    required String action,
  }) async {
    int attempt = 0;

    while (true) {
      try {
        final res = await run().timeout(const Duration(seconds: 45));

        // Retry on temporary gateway issues
        if ((res.statusCode == 502 || res.statusCode == 503 || res.statusCode == 504) && attempt < retries) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }

        return res;
      } catch (e, st) {
        final canRetry = attempt < retries && (e is TimeoutException || e is SocketException || e is http.ClientException);

        if (canRetry) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }

        // Throw friendly (no raw technical details)
        throw _networkFriendly(e, st: st, action: action);
      }
    }
  }

  /* --------------------- public API --------------------- */

  /// Create one backend order per cart item.
  /// Status is typically:
  /// - OrderStatus.confirmed when payment succeeds
  /// - OrderStatus.pending when payment was not completed
  Future<void> createOrdersFromCart({
    required List<CartModel> cartItems,
    Address? address,
    required OrderStatus status,
    String? deliveryMethod,
  }) async {
    await createOrdersFromCartWithRefs(
      cartItems: cartItems,
      address: address,
      status: status,
      deliveryMethod: deliveryMethod,
    );
  }

  /// Same as [createOrdersFromCart] but returns created order ids (for escrow, etc.).
  Future<List<CreatedOrderRef>> createOrdersFromCartWithRefs({
    required List<CartModel> cartItems,
    Address? address,
    required OrderStatus status,
    String? deliveryMethod,
  }) async {
    if (cartItems.isEmpty) return [];

    final uri = ApiConfig.endpoint('/orders');
    final headers = await _headers();

    final addrId = address != null ? int.tryParse(address.id) ?? 0 : 0;

    final out = <CreatedOrderRef>[];

    for (final item in cartItems) {
      final rawDescription = item.description.isNotEmpty
          ? item.description
          : (item.comment ?? '');
      var description = _withDeliveryMethod(rawDescription, deliveryMethod);
      description = _withListingIdTag(description, item);
      // Match backend: send merchantUid (Firebase UID) and let server resolve to numeric user.id
      final body = jsonEncode({
        'ItemName': item.name,
        'ItemImage': item.image,
        'Category': 'other',
        'Price': item.price.round(),
        'Quantity': item.quantity,
        'Description': description,
        'Status': orderStatusToApi(status),
        'merchantUid': item.merchantId,
        // Helps backend / GET orders expose marketplace listing id; ignored if API strips unknown keys.
        if (item.serviceType == 'marketplace' && item.item > 0) 'ItemId': item.item,
        if (addrId > 0) 'addressId': addrId,
      });

      final r = await _retry(
        () => http.post(uri, headers: headers, body: body),
        action: 'place your order',
      );

      if (r.statusCode < 200 || r.statusCode >= 300) {
        dev.log(
          '[OrderService] create order failed: status=${r.statusCode} body=${_safeBodyForLogs(r.body)}',
          name: 'OrderService',
        );
        debugPrint('[OrderService] create order failed: status=${r.statusCode} body=${_safeBodyForLogs(r.body)}');
        _bad(r, action: 'place your order');
      }

      String createdOrderId = '';
      String createdOrderNumber = '';
      try {
        final decoded = jsonDecode(r.body);
        if (decoded is Map) {
          final data = decoded['data'] is Map ? decoded['data'] as Map : decoded;
          createdOrderId = _firstStringFromMap(data, const [
            'id',
            '_id',
            'Id',
            'ID',
            'orderId',
            'OrderId',
            'OrderID',
            'order_id',
          ]);
          createdOrderNumber = _firstStringFromMap(data, const [
            'orderNumber',
            'OrderNumber',
            'orderNo',
            'OrderNo',
            'number',
            'Number',
          ]);
        }
      } catch (_) {}

      final fallbackId = createdOrderId.isNotEmpty
          ? createdOrderId
          : 'new_${item.merchantId}_${DateTime.now().millisecondsSinceEpoch}';
      final fallbackOrderNo =
          createdOrderNumber.isNotEmpty ? createdOrderNumber : item.name.trim();

      await _notifyOrderActivity(
        orderId: fallbackId,
        orderNumber: fallbackOrderNo,
        status: status,
        changed: false,
        isIncomingForMerchant: false,
        orderMarkedShippedByMerchant: false,
        itemName: item.name,
      );
      await _upsertOrderStatusCache(orderId: fallbackId, status: status);

      out.add(CreatedOrderRef(
        orderId: fallbackId,
        orderNumber: fallbackOrderNo,
        item: item,
      ));
    }

    return out;
  }

  /// Embeds marketplace SQL id so `OrderItem` can parse `itemSqlId` from Description if API omits ItemId.
  String _withListingIdTag(String description, CartModel item) {
    if (item.serviceType != 'marketplace' || item.item <= 0) return description;
    if (RegExp(r'\[ListingId:\s*\d+\]', caseSensitive: false).hasMatch(description)) {
      return description;
    }
    final tag = '[ListingId: ${item.item}]';
    final d = description.trim();
    if (d.isEmpty) return tag;
    return '$d $tag';
  }

  String _withDeliveryMethod(String description, String? deliveryMethod) {
    final base = description.trim();
    final method = (deliveryMethod ?? '').trim();
    if (method.isEmpty) return base;
    if (RegExp(r'\[delivery:\s*', caseSensitive: false).hasMatch(base)) {
      return base;
    }
    final tag = '[Delivery: $method]';
    if (base.isEmpty) return tag;
    return '$base $tag';
  }

  Future<List<OrderItem>> _fetchOrdersFromPath({
    required String path,
    required Map<String, String> headers,
    Map<String, String>? queryParameters,
  }) async {
    final uri = ApiConfig.endpoint(path).replace(queryParameters: queryParameters);
    final r = await _retry(() => http.get(uri, headers: headers), action: 'load your orders');

    if (r.statusCode == 404) return <OrderItem>[];
    if (r.statusCode == 403) return <OrderItem>[];
    if (r.statusCode != 200) _bad(r, action: 'load your orders');

    final decoded = jsonDecode(r.body);
    final List<dynamic> list = decoded is List
        ? decoded
        : (decoded is Map && decoded['data'] is List)
            ? (decoded['data'] as List)
            : (decoded is Map && decoded['orders'] is List)
                ? (decoded['orders'] as List)
                : <dynamic>[];

    return list
        .whereType<Map>()
        .map((m) => OrderItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  // Chooses the right “me” endpoint by role.
  Future<List<OrderItem>> getMyOrders({OrderStatus? status}) async {
    final isMerchant = await _isMerchant();
    final qp = status != null ? {'status': orderStatusToApi(status)} : null;
    final h = await _headers();

    try {
      final byId = <String, OrderItem>{};
      final incomingMerchantOrderIds = <String>{};

      final customerOrders = await _fetchOrdersFromPath(
        path: '/orders/me',
        headers: h,
        queryParameters: qp,
      );
      for (final o in customerOrders) {
        byId[o.id] = o;
      }

      if (isMerchant) {
        final merchantOrders = await _fetchOrdersFromPath(
          path: '/orders/merchant/me',
          headers: h,
          queryParameters: qp,
        );
        for (final o in merchantOrders) {
          byId[o.id] = o;
          incomingMerchantOrderIds.add(o.id);
        }
      }

      final all = byId.values.toList();

      // If backend ignored the filter, narrow client-side.
      await _syncOrderStatusNotifications(
        all,
        incomingMerchantOrderIds: incomingMerchantOrderIds,
      );
      if (status != null) {
        return all.where((o) => o.status == status).toList();
      }
      return all;
    } catch (e, st) {
      dev.log('[OrderService] JSON parse error', name: 'OrderService', error: e, stackTrace: st);
      throw FriendlyApiException('We couldn’t load your orders. Please check your internet connection and try again.');
    }
  }

  // PATCH /orders/{id}/status (works for either role if permitted server-side)
  Future<void> updateStatus(String id, OrderStatus next) async {
    if (id.trim().isEmpty) {
      throw FriendlyApiException('Invalid order. Please refresh and try again.');
    }

    final u = ApiConfig.endpoint('/orders/$id/status');
    final h = await _headers();

    // keep your server's expected key casing
    final body = jsonEncode({'Status': orderStatusToApi(next)});

    final r = await _retry(() => http.patch(u, headers: h, body: body), action: 'update the order');
    if (r.statusCode < 200 || r.statusCode >= 300) _bad(r, action: 'update the order');

    final meta = await _resolveOrderMeta(id);
    final isMerch = await _isMerchant();
    await _notifyOrderActivity(
      orderId: id,
      orderNumber: meta.$1,
      status: next,
      changed: true,
      isIncomingForMerchant: isMerch,
      orderMarkedShippedByMerchant:
          isMerch && next == OrderStatus.delivered,
      itemName: meta.$2,
    );
    await _upsertOrderStatusCache(orderId: id, status: next);
  }

  // Cancel, else delete as fallback.
  Future<bool> cancelOrMarkCancelled(String id) async {
    try {
      await updateStatus(id, OrderStatus.cancelled);
      return true;
    } on AuthRequiredException {
      rethrow;
    } on FriendlyApiException {
      rethrow;
    } catch (_) {
      // fallback: delete endpoint
      final u = ApiConfig.endpoint('/orders/$id');
      final h = await _headers();
      final r = await _retry(() => http.delete(u, headers: h), action: 'cancel the order');
      if (r.statusCode < 200 || r.statusCode >= 300) _bad(r, action: 'cancel the order');
      final meta = await _resolveOrderMeta(id);
      await _notifyOrderActivity(
        orderId: id,
        orderNumber: meta.$1,
        status: OrderStatus.cancelled,
        changed: true,
        isIncomingForMerchant: false,
        orderMarkedShippedByMerchant: false,
        itemName: meta.$2,
      );
      await _upsertOrderStatusCache(orderId: id, status: OrderStatus.cancelled);
      return false;
    }
  }
}

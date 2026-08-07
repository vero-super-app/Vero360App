import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/GeneralModels/order_model.dart';

/// Shared newest-first sort + order-number search for order list screens.
class OrderListHelpers {
  OrderListHelpers._();

  static final DateFormat _dateSearch = DateFormat('dd MMM yyyy');
  static final DateFormat _dateSearchAlt = DateFormat('yyyy-MM-dd');
  static final DateFormat _dateTime = DateFormat('dd MMM yyyy, HH:mm');

  static int compareNewestFirst(OrderItem a, OrderItem b) {
    final ad = a.orderDate;
    final bd = b.orderDate;
    if (ad == null && bd == null) return b.id.compareTo(a.id);
    if (ad == null) return 1;
    if (bd == null) return -1;
    final cmp = bd.compareTo(ad);
    if (cmp != 0) return cmp;
    return b.id.compareTo(a.id);
  }

  static void sortNewestFirst(List<OrderItem> items) {
    items.sort(compareNewestFirst);
  }

  /// Matches order number, id, item name, or common date formats.
  static bool matchesSearch(OrderItem o, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (o.orderNumber.toLowerCase().contains(q)) return true;
    if (o.id.toLowerCase().contains(q)) return true;
    if (o.itemName.toLowerCase().contains(q)) return true;
    final d = o.orderDate;
    if (d != null) {
      final local = d.toLocal();
      if (_dateSearch.format(local).toLowerCase().contains(q)) return true;
      if (_dateSearchAlt.format(local).contains(q)) return true;
      if (_dateTime.format(local).toLowerCase().contains(q)) return true;
    }
    return false;
  }

  static InputDecoration searchDecoration({
    required String hint,
    required VoidCallback? onClear,
    bool hasQuery = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF6B778C)),
      suffixIcon: hasQuery
          ? IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onClear,
            )
          : null,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE8ECF2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFF8A00), width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

import 'dart:convert';

enum OrderStatus { pending, confirmed, delivered, cancelled }
enum OrderCategory { food, other }
enum PaymentStatus { paid, unpaid, pending }

OrderStatus orderStatusFrom(String? v) {
  final s = (v ?? '').toLowerCase().trim();
  switch (s) {
    case 'confirmed':  return OrderStatus.confirmed;
    case 'delivered':  return OrderStatus.delivered;
    case 'cancelled':
    case 'canceled':   return OrderStatus.cancelled;
    case 'pending':
    default:           return OrderStatus.pending;
  }
}

String orderStatusToApi(OrderStatus s) {
  switch (s) {
    case OrderStatus.confirmed: return 'confirmed';
    case OrderStatus.delivered: return 'delivered';
    case OrderStatus.cancelled: return 'cancelled';
    case OrderStatus.pending:   return 'pending';
  }
}

OrderCategory orderCategoryFrom(String? v) {
  final s = (v ?? '').toLowerCase().trim();
  return s == 'food' ? OrderCategory.food : OrderCategory.other;
}

PaymentStatus paymentStatusFrom(String? v) {
  final s = (v ?? '').toLowerCase().trim();
  switch (s) {
    case 'paid':    return PaymentStatus.paid;
    case 'pending': return PaymentStatus.pending;
    case 'unpaid':
    default:        return PaymentStatus.unpaid;
  }
}

class OrderItem {
  final String id;               // "ID" or "id"
  final String orderNumber;      // "OrderNumber"
  final String itemName;
  final String itemImage;
  final OrderCategory category;
  final int price;
  final int quantity;
  final String description;
  final OrderStatus status;
  final PaymentStatus paymentStatus;

  // Merchant
  final int merchantId;
  final String? merchantName;
  final String? merchantPhone;
  final double? merchantAvgRating;

  // Address
  final String? addressCity;
  final String? addressDescription;

  // Date
  final DateTime? orderDate;

  int get total => price * quantity;

  OrderItem({
    required this.id,
    required this.orderNumber,
    required this.itemName,
    required this.itemImage,
    required this.category,
    required this.price,
    required this.quantity,
    required this.description,
    required this.status,
    required this.paymentStatus,
    required this.merchantId,
    this.merchantName,
    this.merchantPhone,
    this.merchantAvgRating,
    this.addressCity,
    this.addressDescription,
    this.orderDate,
  });

  static T? _first<T>(Map m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) return m[k] as T?;
    }
    return null;
  }

  factory OrderItem.fromJson(Map<String, dynamic> m) {
    // id & order number
    final idAny = _first(m, ['ID','id','orderId','OrderId']);
    final idStr = idAny?.toString() ?? '';
    final orderNo = _first<String>(m, ['OrderNumber','orderNumber']) ?? '#';

    // basics
    final name  = _first<String>(m, ['ItemName','itemName']) ?? 'Item';
    final img   = _first<String>(m, ['ItemImage','itemImage']) ?? '';
    final cat   = orderCategoryFrom(_first<String>(m, ['Category','category']));
    final price = int.tryParse((_first(m, ['Price','price']) ?? 0).toString()) ?? 0;
    final qty   = int.tryParse((_first(m, ['Quantity','quantity']) ?? 1).toString()) ?? 1;
    final desc  = _first<String>(m, ['Description','description']) ?? '';
    final stat  = orderStatusFrom(_first<String>(m, ['Status','status']));
    final pay   = paymentStatusFrom(_first<String>(m, ['paymentStatus','PaymentStatus']));

    // merchant block
    int merchId = int.tryParse((_first(m, ['merchantId','MerchantId']) ?? 0).toString()) ?? 0;
    String? merchName;
    String? merchPhone;
    double? merchAvg;

    final merchRaw = _first<Map>(m, ['merchant','Merchant']);
    if (merchRaw != null) {
      merchId    = int.tryParse((merchRaw['id'] ?? merchId).toString()) ?? merchId;
      merchName  = merchRaw['name']?.toString();
      merchPhone = merchRaw['phone']?.toString();
      merchAvg   = double.tryParse((merchRaw['averageRating'] ?? merchRaw['avgRating'] ?? '0').toString());
    }

    // address block
    String? addrCity;
    String? addrDesc;
    final addrRaw = _first<Map>(m, ['address','Address']);
    if (addrRaw != null) {
      addrCity = addrRaw['city']?.toString();
      addrDesc = addrRaw['description']?.toString();
    }

    // dates
    DateTime? date;
    final dRaw = _first<String>(m, ['OrderDate','orderDate','createdAt','CreatedAt']);
    if (dRaw != null) { try { date = DateTime.parse(dRaw); } catch (_) {} }

    return OrderItem(
      id: idStr,
      orderNumber: orderNo,
      itemName: name,
      itemImage: img,
      category: cat,
      price: price,
      quantity: qty,
      description: desc,
      status: stat,
      paymentStatus: pay,
      merchantId: merchId,
      merchantName: merchName,
      merchantPhone: merchPhone,
      merchantAvgRating: merchAvg,
      addressCity: addrCity,
      addressDescription: addrDesc,
      orderDate: date,
    );
  }

  Map<String, dynamic> toStatusPatch(OrderStatus next) =>
      {'Status': orderStatusToApi(next)};
}

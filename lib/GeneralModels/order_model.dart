
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

  // Treat common “success” variants (PayChangu, backend enums, etc.) as PAID
  if (s == 'paid' ||
      s == 'success' ||
      s == 'successful' ||
      s == 'completed' ||
      s == 'complete' ||
      s == 'paid_out') {
    return PaymentStatus.paid;
  }

  // Explicit pending / processing states
  if (s == 'pending' ||
      s == 'processing' ||
      s == 'awaiting_payment' ||
      s == 'awaiting') {
    return PaymentStatus.pending;
  }

  // Fallback – anything else counts as unpaid
  return PaymentStatus.unpaid;
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

  /// Optional numeric marketplace listing id (SQL id) if backend includes it,
  /// e.g. ItemId / itemId. Used to mark items as sold automatically.
  final int? itemSqlId;

  // Merchant
  final int merchantId;
  /// Firebase UID when available (for lookup in Firestore users/{uid}).
  final String? merchantUid;
  final String? merchantName;
  final String? merchantPhone;
  final double? merchantAvgRating;
  final String? customerUid;
  final String? customerName;
  final String? customerPhone;

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
    this.merchantUid,
    this.itemSqlId,
    this.merchantName,
    this.merchantPhone,
    this.merchantAvgRating,
    this.customerUid,
    this.customerName,
    this.customerPhone,
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
    // Be tolerant of different backend payment keys and value types (string / number / bool).
    final rawPay = _first(m, [
      'paymentStatus',
      'PaymentStatus',
      'payment_status',
      'Payment_status',
      'payment',
      'Payment',
    ]);
    final pay   = paymentStatusFrom(rawPay?.toString());

    // Optional: marketplace listing id from backend (many API shapes)
    final rawItemId = _first(m, [
      'ItemId',
      'itemId',
      'listingId',
      'ListingId',
      'marketplaceItemId',
      'MarketplaceItemId',
      'productId',
      'ProductId',
      'sqlItemId',
      'SqlItemId',
    ]);
    final nestedItem = _first<Map>(m, ['item', 'Item', 'marketplaceItem', 'MarketplaceItem']);
    final nestedId = nestedItem != null
        ? _first(nestedItem, ['id', 'Id', 'ID', 'listingId', 'ListingId'])
        : null;
    final parsedItemId = rawItemId != null
        ? int.tryParse(rawItemId.toString())
        : (nestedId != null ? int.tryParse(nestedId.toString()) : null);
    final listingFromDesc = _listingIdFromDescription(desc);

    // merchant block
    int merchId = int.tryParse((_first(m, ['merchantId','MerchantId']) ?? 0).toString()) ?? 0;
    String? merchUid;
    String? merchName;
    String? merchPhone;
    double? merchAvg;
    String? customerUid = _first<String>(m, [
      'customerUid',
      'CustomerUid',
      'buyerUid',
      'BuyerUid',
      'customer_id',
      'buyer_id',
    ]);
    String? customerName = _first<String>(m, ['customerName', 'CustomerName', 'buyerName', 'BuyerName']);
    String? customerPhone = _first<String>(m, [
      'customerPhone',
      'CustomerPhone',
      'buyerPhone',
      'BuyerPhone',
      'customer_phone',
      'Customer_phone',
      'buyer_phone',
      'Buyer_phone',
      'customerPhoneNumber',
      'CustomerPhoneNumber',
      'buyerPhoneNumber',
      'BuyerPhoneNumber',
      'customerMobile',
      'CustomerMobile',
      'buyerMobile',
      'BuyerMobile',
      'phoneNumber',
      'PhoneNumber',
      'phone_number',
      'Phone_number',
      'phone',
      'Phone',
      'mobile',
      'Mobile',
    ]);

    final merchRaw = _first<Map>(m, ['merchant','Merchant']);
    if (merchRaw != null) {
      merchId    = int.tryParse((merchRaw['id'] ?? merchId).toString()) ?? merchId;
      merchUid   = _first<String>(merchRaw, ['uid','merchantUid','firebaseUid','userId']);
      merchName  = merchRaw['name']?.toString();
      merchPhone = merchRaw['phone']?.toString();
      merchAvg   = double.tryParse((merchRaw['averageRating'] ?? merchRaw['avgRating'] ?? '0').toString());
    }

    final customerRaw = _first<Map>(m, ['customer', 'Customer', 'buyer', 'Buyer', 'user', 'User']);
    if (customerRaw != null) {
      customerUid ??= _first<String>(customerRaw, [
        'uid',
        'buyerUid',
        'customerUid',
        'firebaseUid',
        'userId',
        'id',
      ]);
      customerName ??= customerRaw['name']?.toString();
      customerName ??= customerRaw['fullName']?.toString();
      customerPhone ??= customerRaw['phone']?.toString();
      customerPhone ??= customerRaw['mobile']?.toString();
      customerPhone ??= customerRaw['phoneNumber']?.toString();
      customerPhone ??= customerRaw['phone_number']?.toString();
      final contact = customerRaw['contact'];
      if (contact is Map) {
        customerPhone ??= contact['phone']?.toString();
        customerPhone ??= contact['mobile']?.toString();
        customerPhone ??= contact['phoneNumber']?.toString();
        customerPhone ??= contact['phone_number']?.toString();
      }
    }

    // address block
    String? addrCity;
    String? addrDesc;
    final addrRaw = _first<Map>(m, ['address','Address']);
    if (addrRaw != null) {
      addrCity = addrRaw['city']?.toString();
      addrDesc = addrRaw['description']?.toString();
      customerPhone ??= addrRaw['phone']?.toString();
      customerPhone ??= addrRaw['mobile']?.toString();
      customerPhone ??= addrRaw['phoneNumber']?.toString();
      customerPhone ??= addrRaw['recipientPhone']?.toString();
      customerPhone ??= addrRaw['recipient_phone']?.toString();
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
      merchantUid: merchUid?.trim().isEmpty == true ? null : merchUid?.trim(),
      itemSqlId: parsedItemId ?? listingFromDesc,
      merchantName: merchName,
      merchantPhone: merchPhone,
      merchantAvgRating: merchAvg,
      customerUid: customerUid?.trim().isEmpty == true ? null : customerUid?.trim(),
      customerName: customerName,
      customerPhone: customerPhone?.trim().isEmpty == true ? null : customerPhone?.trim(),
      addressCity: addrCity,
      addressDescription: addrDesc,
      orderDate: date,
    );
  }

  Map<String, dynamic> toStatusPatch(OrderStatus next) =>
      {'Status': orderStatusToApi(next)};

  /// Fallback when API omits ItemId: we embed `[ListingId: N]` in Description at checkout.
  static int? _listingIdFromDescription(String? description) {
    final s = (description ?? '').trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'\[ListingId:\s*(\d+)\]', caseSensitive: false).firstMatch(s);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  }
}

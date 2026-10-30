import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/features/DigitalServices/digital_product.dart';
import 'package:vero360_app/features/DigitalServices/presentation/digital_kyc_upload_section.dart';
import 'package:vero360_app/GernalServices/firebase_wallet_service.dart';
import 'package:vero360_app/GernalServices/order_party_notification_service.dart';

/// Firestore collection for Digital Services purchases (subscriptions + gift cards).
const String kDigitalServiceOrdersCollection = 'digital_service_orders';

class DigitalOrderFulfillment {
  final String cardDetails;
  final String joiningLink;
  final String notes;
  final List<String> fileUrls;
  final DateTime? sentAt;

  /// Extra credential rows (login, password, email, pin, …) for copy buttons.
  final Map<String, String> extraFields;

  const DigitalOrderFulfillment({
    this.cardDetails = '',
    this.joiningLink = '',
    this.notes = '',
    this.fileUrls = const [],
    this.sentAt,
    this.extraFields = const {},
  });

  bool get hasContent =>
      cardDetails.trim().isNotEmpty ||
      joiningLink.trim().isNotEmpty ||
      notes.trim().isNotEmpty ||
      fileUrls.isNotEmpty ||
      extraFields.values.any((v) => v.trim().isNotEmpty);

  /// Plain text of every delivered field so the buyer can copy once.
  String get copyAllText {
    final buf = StringBuffer();
    void line(String label, String value) {
      final v = value.trim();
      if (v.isEmpty) return;
      buf.writeln('$label:');
      buf.writeln(v);
      buf.writeln();
    }

    line('Card details', cardDetails);
    for (final e in extraFields.entries) {
      line(e.key, e.value);
    }
    line('Joining link', joiningLink);
    line('Notes', notes);
    if (fileUrls.isNotEmpty) {
      line('Files', fileUrls.join('\n'));
    }
    return buf.toString().trim();
  }

  static String _str(dynamic v) => (v ?? '').toString().trim();

  static DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static List<String> _urls(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Admin dashboards store delivery under `fulfillment` or as top-level fields.
  factory DigitalOrderFulfillment.fromOrderData(Map<String, dynamic> d) {
    final rawFulfill = d['fulfillment'];
    final f = rawFulfill is Map
        ? Map<String, dynamic>.from(rawFulfill)
        : const <String, dynamic>{};

    String pick(List<String> keys) {
      for (final k in keys) {
        final fromF = _str(f[k]);
        if (fromF.isNotEmpty) return fromF;
        final fromD = _str(d[k]);
        if (fromD.isNotEmpty) return fromD;
      }
      return '';
    }

    const extraKeyLabels = <String, String>{
      'email': 'Email',
      'username': 'Username',
      'userName': 'Username',
      'login': 'Login',
      'account': 'Account',
      'password': 'Password',
      'pin': 'PIN',
      'code': 'Code',
      'voucher': 'Voucher',
      'giftCode': 'Gift code',
      'phone': 'Phone',
    };

    final extras = <String, String>{};
    final buyerEmail = _str(d['buyerEmail'] ?? d['email']);
    for (final e in extraKeyLabels.entries) {
      var v = _str(f[e.key]);
      if (v.isEmpty && e.key != 'email') {
        v = _str(d[e.key]);
      }
      if (v.isEmpty) continue;
      if (e.key == 'email' && v.toLowerCase() == buyerEmail.toLowerCase()) {
        continue;
      }
      extras.putIfAbsent(e.value, () => v);
    }

    final fileUrls = _urls(f['fileUrls']);
    final topFiles = _urls(d['fileUrls']);

    return DigitalOrderFulfillment(
      cardDetails: pick([
        'cardDetails',
        'card',
        'credentials',
        'loginDetails',
        'accountDetails',
        'details',
        'deliveryDetails',
      ]),
      joiningLink: pick([
        'joiningLink',
        'joinLink',
        'inviteLink',
        'accessLink',
        'link',
        'url',
      ]),
      notes: pick([
        'notes',
        'fulfillmentNotes',
        'message',
        'instructions',
        'adminNote',
        'deliveryNotes',
      ]),
      fileUrls: fileUrls.isNotEmpty ? fileUrls : topFiles,
      sentAt: _asDate(f['sentAt'] ?? d['fulfilledAt'] ?? d['deliveredAt']),
      extraFields: extras,
    );
  }
}

class DigitalServiceOrder {
  final String id;
  final String productKey;
  final String productName;
  final String productSubtitle;
  final String brandTag;
  final String category;
  final String kind;
  final String periodLabel;
  final double? selectedUsd;
  final double amountMwk;
  final String currency;
  final String status;
  final String txRef;
  final String buyerUid;
  final String buyerEmail;
  final bool isGuest;
  final DateTime? createdAt;
  final DateTime? paidAt;
  final DigitalOrderFulfillment fulfillment;

  const DigitalServiceOrder({
    required this.id,
    this.productKey = '',
    this.productName = '',
    this.productSubtitle = '',
    this.brandTag = '',
    this.category = '',
    this.kind = '',
    this.periodLabel = '',
    this.selectedUsd,
    this.amountMwk = 0,
    this.currency = 'MWK',
    this.status = 'pending_payment',
    this.txRef = '',
    this.buyerUid = '',
    this.buyerEmail = '',
    this.isGuest = false,
    this.createdAt,
    this.paidAt,
    this.fulfillment = const DigitalOrderFulfillment(),
  });

  bool get isPaid {
    final s = status.toLowerCase();
    return s == 'paid' || s == 'fulfilled' || s == 'completed' || s == 'delivered';
  }

  bool get isPending {
    final s = status.toLowerCase();
    return s == 'pending_payment' || s == 'pending' || s.isEmpty;
  }

  bool get isFailed {
    final s = status.toLowerCase();
    return s == 'failed' || s == 'cancelled' || s == 'canceled';
  }

  String get statusLabel {
    if (isFailed) return 'Cancelled';
    if (status.toLowerCase() == 'fulfilled' ||
        status.toLowerCase() == 'completed' ||
        status.toLowerCase() == 'delivered' ||
        fulfillment.hasContent) {
      return 'Delivered';
    }
    if (isPaid) return 'Paid · processing';
    return 'Awaiting payment';
  }

  factory DigitalServiceOrder.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};

    DateTime? asDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    double asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }

    String str(dynamic v) => (v ?? '').toString().trim();

    return DigitalServiceOrder(
      id: doc.id,
      productKey: str(d['productKey']),
      productName: str(d['productName']).isEmpty
          ? 'Digital service'
          : str(d['productName']),
      productSubtitle: str(d['productSubtitle']),
      brandTag: str(d['brandTag']),
      category: str(d['category']),
      kind: str(d['kind']),
      periodLabel: str(d['periodLabel']),
      selectedUsd: d['selectedUsd'] == null ? null : asDouble(d['selectedUsd']),
      amountMwk: asDouble(d['amountMwk']),
      currency: str(d['currency']).isEmpty ? 'MWK' : str(d['currency']),
      status: str(d['status']).isEmpty ? 'pending_payment' : str(d['status']),
      txRef: str(d['txRef']),
      buyerUid: str(d['buyerUid']),
      buyerEmail: str(d['buyerEmail'] ?? d['email']),
      isGuest: d['isGuest'] == true,
      createdAt: asDate(d['createdAt']),
      paidAt: asDate(d['paidAt']),
      fulfillment: DigitalOrderFulfillment.fromOrderData(d),
    );
  }
}

class DigitalServiceOrderService {
  DigitalServiceOrderService._();

  static final _col =
      FirebaseFirestore.instance.collection(kDigitalServiceOrdersCollection);

  static Future<String> createPendingOrder({
    required DigitalProduct product,
    required double amountMwk,
    required String txRef,
    required String buyerName,
    required String buyerEmail,
    required String buyerPhone,
    double? selectedUsd,
    DigitalPayoutKycPayload? payoutKyc,
    String paymentProvider = 'pawapay',
  }) async {
    var user = FirebaseAuth.instance.currentUser;
    user ??= (await FirebaseAuth.instance.signInAnonymously()).user;
    if (user == null) {
      throw Exception('Could not start checkout. Please try again.');
    }
    final isGuest = user.isAnonymous;
    final isSubscription = product.fixedMwkPrice != null;
    final isCrypto = product.category.trim().toLowerCase() == 'crypto';
    final kind = isCrypto
        ? 'crypto'
        : (isSubscription ? 'subscription' : 'gift_card');
    final doc = _col.doc();
    await doc.set({
      'productKey': product.key,
      'productName': product.name,
      'productSubtitle': product.subtitle,
      'brandTag': product.brandTag,
      'category': product.category,
      'kind': kind,
      'period': isSubscription ? 'monthly' : null,
      'periodLabel': isSubscription ? '1 month' : null,
      'selectedUsd': selectedUsd,
      'amountMwk': amountMwk,
      'currency': 'MWK',
      'status': 'pending_payment',
      'txRef': txRef,
      'paymentProvider': paymentProvider,
      'buyerUid': isGuest ? '' : user.uid,
      'isGuest': isGuest,
      'buyerName': buyerName,
      'buyerEmail': buyerEmail,
      'buyerPhone': buyerPhone,
      'platformFeeCredited': false,
      'source': 'app',
      if (payoutKyc != null) 'payoutKyc': {
        ...payoutKyc.toMap(),
        'uploadedAt': FieldValue.serverTimestamp(),
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Marks paid, credits full amount to platform (Vero main) wallet.
  static Future<void> activateAfterPayment({
    required String orderId,
    required String txRef,
  }) async {
    final ref = _col.doc(orderId);
    final snap = await ref.get();
    final data = snap.data() ?? const <String, dynamic>{};
    final amount = (data['amountMwk'] as num?)?.toDouble() ?? 0;
    final productName =
        (data['productName'] ?? 'Digital service').toString().trim();
    final alreadyCredited = data['platformFeeCredited'] == true;

    var feeCreditedNow = false;
    if (!alreadyCredited && amount > 0) {
      try {
        await FirebaseWalletService.creditPlatformServiceFee(
          amount: amount,
          description: 'Digital service · $productName',
          reference: txRef.isNotEmpty ? txRef : 'digital:$orderId',
          service: 'digital',
        );
        feeCreditedNow = true;
      } catch (_) {
        // Admin dashboard can backfill via Credit platform fee.
      }
    }

    await ref.set({
      'status': 'paid',
      'txRef': txRef,
      'paidAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (!alreadyCredited && feeCreditedNow) ...{
        'platformFeeCredited': true,
        'platformFeeCreditedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));

    final buyerUid = (data['buyerUid'] ?? '').toString().trim();
    final isGuest = data['isGuest'] == true;
    if (buyerUid.isNotEmpty && !isGuest) {
      await OrderPartyNotificationService.publishDigitalOrderToBuyer(
        buyerUid: buyerUid,
        productName: productName,
        orderId: orderId,
        title: 'Payment received · $productName',
        body:
            'We received your $productName payment. Open My Digital Orders — we will send your details there.',
        type: 'digital_order',
      );
    }
  }

  /// Live list of the signed-in buyer’s digital orders (newest first).
  static Stream<DigitalServiceOrder?> watchById(String orderId) {
    final id = orderId.trim();
    if (id.isEmpty) {
      return Stream<DigitalServiceOrder?>.value(null);
    }
    return _col.doc(id).snapshots().map((snap) {
      if (!snap.exists) return null;
      return DigitalServiceOrder.fromDoc(snap);
    });
  }

  /// Live list of the signed-in buyer’s digital orders (newest first).
  static Stream<List<DigitalServiceOrder>> watchMine() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      return Stream<List<DigitalServiceOrder>>.value(const []);
    }
    return _col
        .where('buyerUid', isEqualTo: uid)
        .limit(80)
        .snapshots()
        .map((snap) {
      final rows = snap.docs.map(DigitalServiceOrder.fromDoc).toList();
      rows.sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return rows;
    });
  }
}

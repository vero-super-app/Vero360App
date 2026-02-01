import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:vero360_app/features/Marketplace/MarkeplaceModel/Latest_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/MarkeplaceMerchantServices/latest_Services.dart';

// ===== Latest Arrivals (API + Firestore image + Cart + Bottomsheet) =====
class LatestArrivalsSection extends StatefulWidget {
  const LatestArrivalsSection({super.key});

  @override
  State<LatestArrivalsSection> createState() => _LatestArrivalsSectionState();
}

class _LatestArrivalsSectionState extends State<LatestArrivalsSection> {
  final _service = LatestArrivalServices();
  late Future<List<LatestArrivalModels>> _future;

  final Map<String, Future<String?>> _imageFutureCache = {};

  static const Color _brandOrange = Color(0xFFFF8A00);

  @override
  void initState() {
    super.initState();
    _future = _service.fetchLatestArrivals();
  }

  String _fmtKwacha(int n) {
    final s = n.toString();
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }

  // =========================
  // IMAGE RESOLVER (Firestore + Storage aware)
  // =========================
  Future<String?> _resolveImageUrl(LatestArrivalModels item) async {
    final raw = item.imageUrl.trim();

    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('data:image/')) return raw;

    if (raw.startsWith('gs://')) {
      try {
        return await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
      } catch (_) {}
    }

    if (raw.isNotEmpty && raw.contains('/') && !raw.contains(' ')) {
      try {
        return await FirebaseStorage.instance.ref(raw).getDownloadURL();
      } catch (_) {}
    }

    Future<String?> tryCol(String col) async {
      try {
        final doc = await FirebaseFirestore.instance.collection(col).doc(item.id).get();
        if (!doc.exists) return null;

        final data = doc.data() ?? {};
        final val = (data['imageUrl'] ?? data['image'] ?? data['thumbnail'] ?? '').toString().trim();
        if (val.isEmpty) return null;

        final temp = LatestArrivalModels(
          id: item.id,
          name: item.name,
          imageUrl: val,
          price: item.price,
        );
        return _resolveImageUrl(temp);
      } catch (_) {
        return null;
      }
    }

    final a = await tryCol('latestarrivals');
    if (a != null) return a;

    final b = await tryCol('latest_arrivals');
    if (b != null) return b;

    return null;
  }

  Future<String?> _imageFuture(LatestArrivalModels item) {
    final key = item.id.isNotEmpty ? item.id : '${item.name}_${item.price}';
    return _imageFutureCache.putIfAbsent(key, () => _resolveImageUrl(item));
  }

  // =========================
  // CART LOGIC
  // =========================
  Future<void> _addToCart(LatestArrivalModels item, {int qty = 1}) async {
    if (qty <= 0) return;

    final user = FirebaseAuth.instance.currentUser;
    final resolvedImage = await _resolveImageUrl(item) ?? item.imageUrl;

    // Logged in -> Firestore cart
    if (user != null) {
      final uid = user.uid;
      final docId = (item.id.isNotEmpty) ? item.id : item.name;

      final docRef = FirebaseFirestore.instance
          .collection('carts')
          .doc(uid)
          .collection('items')
          .doc(docId);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (snap.exists) {
          tx.update(docRef, {
            'qty': FieldValue.increment(qty),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          tx.set(docRef, {
            'id': item.id,
            'name': item.name,
            'price': item.price,
            'imageUrl': resolvedImage,
            'qty': qty,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} added to cart')),
      );
      return;
    }

    // Guest -> SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    const key = 'guest_cart_items';

    final raw = prefs.getString(key) ?? '[]';
    final decoded = jsonDecode(raw);
    final List list = decoded is List ? decoded : <dynamic>[];

    final idx = list.indexWhere((e) =>
        e is Map &&
        ((e['id']?.toString() ?? '') == item.id || (e['name']?.toString() ?? '') == item.name));

    if (idx >= 0) {
      final m = Map<String, dynamic>.from(list[idx] as Map);
      final currentQty = int.tryParse(m['qty']?.toString() ?? '1') ?? 1;
      m['qty'] = currentQty + qty;
      list[idx] = m;
    } else {
      list.add({
        'id': item.id,
        'name': item.name,
        'price': item.price,
        'imageUrl': resolvedImage,
        'qty': qty,
      });
    }

    await prefs.setString(key, jsonEncode(list));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.name} added to cart (guest)')),
    );
  }

  // =========================
  // BOTTOM SHEETS
  // =========================
  void _showOptions(BuildContext context, LatestArrivalModels item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Choose an action',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.shopping_cart, color: Colors.green),
            title: const Text('Add to cart'),
            onTap: () async {
              Navigator.pop(context);
              await _addToCart(item, qty: 1);
            },
          ),
          const Divider(height: 0),
          ListTile(
            leading: Icon(Icons.info_outline_rounded, color: _brandOrange),
            title: const Text('More details'),
            onTap: () {
              Navigator.pop(context);
              _showDetails(context, item);
            },
          ),
        ]),
      ),
    );
  }

  void _showDetails(BuildContext context, LatestArrivalModels item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _LatestDetailsSheet(
        item: item,
        imageFuture: _imageFuture(item),
        brandOrange: _brandOrange,
        fmtKwacha: _fmtKwacha,
        onAdd: (qty) => _addToCart(item, qty: qty),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(5, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Latest Arrivals",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          FutureBuilder<List<LatestArrivalModels>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Could not load arrivals.\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }

              final items = snap.data ?? const <LatestArrivalModels>[];
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No items yet.',
                        style: TextStyle(color: Colors.red)),
                  ),
                );
              }

              final width = MediaQuery.of(context).size.width;
              final cols = width >= 1200
                  ? 4
                  : width >= 800
                      ? 3
                      : 2;
              final ratio = width >= 1200
                  ? 0.95
                  : width >= 800
                      ? 0.85
                      : 0.72;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: ratio,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final it = items[i];
                  return _ProductCardFromApi(
                    item: it,
                    priceText: 'MWK ${_fmtKwacha(it.price)}',
                    brandOrange: _brandOrange,
                    imageFuture: _imageFuture(it),
                    onOptions: () => _showOptions(context, it),
                    onOpen: () => _showDetails(context, it),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProductCardFromApi extends StatelessWidget {
  final LatestArrivalModels item;
  final String priceText;
  final Color brandOrange;

  final Future<String?> imageFuture;
  final VoidCallback onOptions;
  final VoidCallback onOpen;

  const _ProductCardFromApi({
    required this.item,
    required this.priceText,
    required this.brandOrange,
    required this.imageFuture,
    required this.onOptions,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      elevation: 0.6,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: FutureBuilder<String?>(
                  future: imageFuture,
                  builder: (ctx, snap) {
                    final url = (snap.data ?? '').trim();

                    if (url.startsWith('data:image/')) {
                      try {
                        final bytes = base64Decode(url.split(',').last);
                        return Image.memory(bytes, fit: BoxFit.cover);
                      } catch (_) {
                        return const _ImgPlaceholder();
                      }
                    }

                    if (url.isEmpty) return const _ImgPlaceholder();

                    return Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (ctx, child, prog) => prog == null
                          ? child
                          : const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                      errorBuilder: (_, __, ___) => const _ImgPlaceholder(),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          priceText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    onPressed: onOptions,
                    icon: Icon(Icons.add_circle, color: brandOrange),
                    tooltip: 'Add / Options',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImgPlaceholder extends StatelessWidget {
  const _ImgPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEDEDED),
      child: const Center(
        child: Icon(Icons.image_not_supported_rounded, color: Colors.black38),
      ),
    );
  }
}

// =====================
// DETAILS SHEET
// =====================
class _LatestDetailsSheet extends StatefulWidget {
  final LatestArrivalModels item;
  final Future<String?> imageFuture;
  final Color brandOrange;
  final String Function(int) fmtKwacha;
  final Future<void> Function(int qty) onAdd;

  const _LatestDetailsSheet({
    required this.item,
    required this.imageFuture,
    required this.brandOrange,
    required this.fmtKwacha,
    required this.onAdd,
  });

  @override
  State<_LatestDetailsSheet> createState() => _LatestDetailsSheetState();
}

class _LatestDetailsSheetState extends State<_LatestDetailsSheet> {
  int _qty = 1;
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 5,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: FutureBuilder<String?>(
                future: widget.imageFuture,
                builder: (ctx, snap) {
                  final url = (snap.data ?? '').trim();

                  if (url.startsWith('data:image/')) {
                    try {
                      final bytes = base64Decode(url.split(',').last);
                      return Image.memory(bytes, fit: BoxFit.cover);
                    } catch (_) {
                      return const _ImgPlaceholder();
                    }
                  }

                  if (url.isEmpty) return const _ImgPlaceholder();

                  return Image.network(
                    url,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, prog) => prog == null
                        ? child
                        : const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                    errorBuilder: (_, __, ___) => const _ImgPlaceholder(),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Text(
                  widget.item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "MWK ${widget.fmtKwacha(widget.item.price)}",
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.green,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Text("Quantity", style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                onPressed: _qty <= 1 ? null : () => setState(() => _qty -= 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text("$_qty", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              IconButton(
                onPressed: () => setState(() => _qty += 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text("Close", style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _adding
                      ? null
                      : () async {
                          setState(() => _adding = true);
                          try {
                            await widget.onAdd(_qty);
                            if (!mounted) return;
                            Navigator.pop(context);
                          } finally {
                            if (mounted) setState(() => _adding = false);
                          }
                        },
                  icon: _adding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.shopping_cart_outlined),
                  label: const Text("Add to cart", style: TextStyle(fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.brandOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
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

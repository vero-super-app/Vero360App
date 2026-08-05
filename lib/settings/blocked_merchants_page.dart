import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GernalServices/blocked_merchant_service.dart';

/// Manage merchants the signed-in user has hidden from their app.
class BlockedMerchantsPage extends StatefulWidget {
  const BlockedMerchantsPage({super.key});

  @override
  State<BlockedMerchantsPage> createState() => _BlockedMerchantsPageState();
}

class _BlockedMerchantsPageState extends State<BlockedMerchantsPage> {
  static const _orange = Color(0xFFFF8A00);
  static const _navy = Color(0xFF16284C);

  bool _loading = true;
  List<BlockedMerchantRecord> _rows = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final rows = await BlockedMerchantService.listBlocked();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _unblock(BlockedMerchantRecord row) async {
    await BlockedMerchantService.unblockMerchant(row.merchantId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Unblocked ${row.displayName ?? 'merchant'}',
        ),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.yMMMd();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Blocked merchants'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : RefreshIndicator(
              color: _orange,
              onRefresh: _reload,
              child: _rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        Icon(Icons.block_rounded,
                            size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          'No blocked merchants',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'When you block a merchant from their shop page, their items, stories, and promotions are hidden until you unblock them here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        final name = (row.displayName ?? '').trim().isNotEmpty
                            ? row.displayName!.trim()
                            : 'Merchant';
                        final when = row.blockedAt != null
                            ? dateFmt.format(row.blockedAt!)
                            : null;
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: Color(0xFFE2E6EF)),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: Colors.red.shade50,
                              child: Icon(Icons.storefront_outlined,
                                  color: Colors.red.shade700),
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              when != null
                                  ? 'Blocked $when'
                                  : 'Hidden from your feed',
                            ),
                            trailing: TextButton(
                              onPressed: () => _unblock(row),
                              child: const Text('Unblock'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

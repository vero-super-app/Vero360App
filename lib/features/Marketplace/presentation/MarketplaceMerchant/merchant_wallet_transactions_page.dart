import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GeneralModels/wallet_model.dart';

class MerchantWalletTransactionsPage extends StatefulWidget {
  final String walletId;
  final String merchantName;
  final String serviceType;

  const MerchantWalletTransactionsPage({
    super.key,
    required this.walletId,
    required this.merchantName,
    required this.serviceType,
  });

  @override
  State<MerchantWalletTransactionsPage> createState() =>
      _MerchantWalletTransactionsPageState();
}

class _MerchantWalletTransactionsPageState
    extends State<MerchantWalletTransactionsPage> {
  final _firestore = FirebaseFirestore.instance;

  String _filter = 'all'; // all | credit(refunds) | payout | completed
  final NumberFormat _mwkFormat = NumberFormat('#,##0', 'en');

  Query<Map<String, dynamic>> _baseQuery() {
    // Keep the Firestore query simple so it doesn't require composite indexes.
    // We apply type filters and sorting client-side.
    return _firestore
        .collection('wallet_transactions')
        .where('walletId', isEqualTo: widget.walletId);
  }

  void _showTransactionDetails(WalletTransaction transaction) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transaction Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  transaction.type == 'credit'
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  color: transaction.type == 'credit'
                      ? Colors.green
                      : Colors.orange,
                ),
                title: Text(
                  transaction.description,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  DateFormat('MMM dd, yyyy HH:mm').format(transaction.createdAt),
                ),
              ),
              const Divider(),
              _detailRow('Amount', 'MWK ${_mwkFormat.format(transaction.amount)}'),
              _detailRow('Type', transaction.type.toUpperCase()),
              _detailRow('Status', transaction.status.toUpperCase()),
              _detailRow('Reference', transaction.reference),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(WalletTransaction t) {
    final isCredit = t.type.toLowerCase() == 'credit';
    final amountPrefix = isCredit ? '+' : '-';
    final amountColor = isCredit ? Colors.green : Colors.red;

    Color statusColor;
    IconData statusIcon;
    switch (t.status.toLowerCase()) {
      case 'completed':
      case 'success':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        break;
      case 'failed':
      case 'declined':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.receipt;
    }

    return ListTile(
      onTap: () => _showTransactionDetails(t),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isCredit
              ? Colors.green.withOpacity(0.1)
              : Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isCredit ? Icons.arrow_downward : Icons.arrow_upward,
          color: isCredit ? Colors.green : Colors.red,
        ),
      ),
      title: Text(
        t.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Row(
        children: [
          Icon(statusIcon, size: 16, color: statusColor),
          const SizedBox(width: 6),
          Text(
            t.status.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            DateFormat('MMM dd, HH:mm').format(t.createdAt),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      trailing: Text(
        '$amountPrefix MWK ${_mwkFormat.format(t.amount)}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: amountColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF16284C),
        foregroundColor: Colors.white,
        title: Text('${widget.serviceType.toUpperCase()} Transactions'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('All')),
                      ButtonSegment(value: 'credit', label: Text('Refunds')),
                      ButtonSegment(value: 'payout', label: Text('Payouts')),
                      ButtonSegment(value: 'completed', label: Text('Completed')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) {
                      setState(() => _filter = s.first);
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _baseQuery().snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF8A00)),
                  );
                }
                if (snap.hasError) {
                  // Avoid surfacing internal Firestore details or index URLs to users.
                  return const Center(
                    child: Text(
                      'Failed to load transactions. Please try again later.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      _filter == 'all'
                          ? 'No transactions yet'
                          : _filter == 'credit'
                              ? 'No refund transactions yet'
                              : _filter == 'payout'
                                  ? 'No payout transactions yet'
                                  : 'No completed transactions yet',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  );
                }

                var txs = docs.map((d) {
                  final data = d.data();
                  return WalletTransaction.fromMap({
                    ...data,
                    'transactionId': d.id,
                  });
                }).toList();

                // Apply filter client-side to avoid extra Firestore indexes.
                if (_filter == 'credit') {
                  txs = txs
                      .where((t) => t.type.toLowerCase() == 'credit')
                      .toList();
                } else if (_filter == 'payout') {
                  txs = txs
                      .where((t) => t.type.toLowerCase() == 'payout')
                      .toList();
                } else if (_filter == 'completed') {
                  txs = txs.where((t) {
                    final s = t.status.toLowerCase();
                    return s == 'completed' || s == 'success';
                  }).toList();
                }

                // Sort newest first by createdAt.
                txs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                return ListView.separated(
                  itemCount: txs.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey[200]),
                  itemBuilder: (context, i) => _buildTransactionTile(txs[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/GeneralModels/wallet_model.dart';

class FirebaseWalletService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get or create wallet for merchant
  static Future<WalletModel> getOrCreateWallet({
    required String merchantId,
    required String merchantName,
  }) async {
    try {
      // Check if wallet exists
      final walletQuery = await _firestore
          .collection('wallets')
          .where('userId', isEqualTo: merchantId)
          .limit(1)
          .get();

      if (walletQuery.docs.isNotEmpty) {
        // Return existing wallet
        final walletDoc = walletQuery.docs.first;
        return WalletModel.fromMap({
          ...walletDoc.data(),
          'walletId': walletDoc.id,
        });
      } else {
        // Create new wallet
        final walletId = await _generateWalletId();
        final newWallet = WalletModel(
          walletId: walletId,
          userId: merchantId,
          merchantName: merchantName,
          balance: 0.0,
          pendingBalance: 0.0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transactions: [],
        );

        await _firestore
            .collection('wallets')
            .doc(walletId)
            .set(newWallet.toMap());

        return newWallet;
      }
    } catch (e) {
      print('Error getting/creating wallet: $e');
      rethrow;
    }
  }

  // Generate unique wallet ID
  static Future<String> _generateWalletId() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (DateTime.now().microsecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    return 'WLT$timestamp$random';
  }

  // Get real-time wallet stream
  static Stream<WalletModel?> getWalletStream(String merchantId) {
    try {
      return _firestore
          .collection('wallets')
          .where('userId', isEqualTo: merchantId)
          .limit(1)
          .snapshots()
          .map((snapshot) {
        if (snapshot.docs.isEmpty) return null;
        final doc = snapshot.docs.first;
        return WalletModel.fromMap({
          ...doc.data(),
          'walletId': doc.id,
        });
      });
    } catch (e) {
      print('Error getting wallet stream: $e');
      return Stream.value(null);
    }
  }

  // Debit wallet (for payouts)
  static Future<void> debitWallet({
    required String merchantId,
    required double amount,
    required String description,
    required String reference,
  }) async {
    try {
      // Find wallet for merchant
      final walletQuery = await _firestore
          .collection('wallets')
          .where('userId', isEqualTo: merchantId)
          .limit(1)
          .get();

      if (walletQuery.docs.isEmpty) {
        throw Exception('Wallet not found for merchant');
      }

      final walletDoc = walletQuery.docs.first;
      final walletData = walletDoc.data();
      final currentBalance = (walletData['balance'] ?? 0.0).toDouble();

      if (currentBalance < amount) {
        throw Exception('Insufficient balance');
      }

      // Create transaction
      final transactionId = 'TXN${DateTime.now().millisecondsSinceEpoch}';
      final walletTransaction = WalletTransaction(
        transactionId: transactionId,
        walletId: walletDoc.id,
        type: 'payout',
        amount: amount,
        status: 'pending',
        description: description,
        reference: reference,
        createdAt: DateTime.now(),
      );

      // Update wallet balance and add transaction
      await _firestore.runTransaction((firestoreTransaction) async {
        final walletRef = _firestore.collection('wallets').doc(walletDoc.id);
        final walletSnapshot = await firestoreTransaction.get(walletRef);
        
        if (!walletSnapshot.exists) {
          throw Exception('Wallet not found');
        }

        final data = walletSnapshot.data() as Map<String, dynamic>;
        final newBalance = (data['balance'] ?? 0.0).toDouble() - amount;
        final transactions = List<Map<String, dynamic>>.from(data['transactions'] ?? []);
        
        transactions.add({
          ...walletTransaction.toMap(),
          'createdAt': Timestamp.now(),
        });

        firestoreTransaction.update(walletRef, {
          'balance': newBalance,
          'pendingBalance': FieldValue.increment(amount),
          'updatedAt': Timestamp.now(),
          'transactions': transactions,
        });
      });

      // Also create a separate transaction document
      await _firestore
          .collection('wallet_transactions')
          .doc(transactionId)
          .set({
            ...walletTransaction.toMap(),
            'createdAt': Timestamp.now(),
            'updatedAt': Timestamp.now(),
          });

    } catch (e) {
      print('Error debiting wallet: $e');
      rethrow;
    }
  }

  // Credit wallet (for deposits, refunds, etc.)
  static Future<void> creditWallet({
    required String merchantId,
    required double amount,
    required String description,
    required String reference,
    String type = 'credit',
  }) async {
    try {
      // Find wallet for merchant
      final walletQuery = await _firestore
          .collection('wallets')
          .where('userId', isEqualTo: merchantId)
          .limit(1)
          .get();

      if (walletQuery.docs.isEmpty) {
        throw Exception('Wallet not found for merchant');
      }

      final walletDoc = walletQuery.docs.first;

      // Create transaction
      final transactionId = 'TXN${DateTime.now().millisecondsSinceEpoch}';
      final walletTransaction = WalletTransaction(
        transactionId: transactionId,
        walletId: walletDoc.id,
        type: type,
        amount: amount,
        status: 'completed',
        description: description,
        reference: reference,
        createdAt: DateTime.now(),
      );

      // Update wallet balance and add transaction
      await _firestore.runTransaction((firestoreTransaction) async {
        final walletRef = _firestore.collection('wallets').doc(walletDoc.id);
        final walletSnapshot = await firestoreTransaction.get(walletRef);
        
        if (!walletSnapshot.exists) {
          throw Exception('Wallet not found');
        }

        final data = walletSnapshot.data() as Map<String, dynamic>;
        final newBalance = (data['balance'] ?? 0.0).toDouble() + amount;
        final transactions = List<Map<String, dynamic>>.from(data['transactions'] ?? []);
        
        transactions.add({
          ...walletTransaction.toMap(),
          'createdAt': Timestamp.now(),
        });

        firestoreTransaction.update(walletRef, {
          'balance': newBalance,
          'updatedAt': Timestamp.now(),
          'transactions': transactions,
        });
      });

      // Create separate transaction document
      await _firestore
          .collection('wallet_transactions')
          .doc(transactionId)
          .set({
            ...walletTransaction.toMap(),
            'createdAt': Timestamp.now(),
            'updatedAt': Timestamp.now(),
          });

    } catch (e) {
      print('Error crediting wallet: $e');
      rethrow;
    }
  }

  // Get wallet transactions
  static Stream<List<WalletTransaction>> getTransactionsStream(String walletId) {
    return _firestore
        .collection('wallet_transactions')
        .where('walletId', isEqualTo: walletId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return WalletTransaction.fromMap({
          ...doc.data(),
          'transactionId': doc.id,
        });
      }).toList();
    });
  }

  // Update transaction status (for payouts)
  static Future<void> updateTransactionStatus({
    required String transactionId,
    required String status,
    String? failureReason,
  }) async {
    try {
      await _firestore
          .collection('wallet_transactions')
          .doc(transactionId)
          .update({
            'status': status,
            'updatedAt': Timestamp.now(),
            if (failureReason != null) 'failureReason': failureReason,
          });

      // If transaction is completed and it's a payout, update pending balance
      if (status == 'completed') {
        final txDoc = await _firestore
            .collection('wallet_transactions')
            .doc(transactionId)
            .get();

        if (txDoc.exists) {
          final txData = txDoc.data() as Map<String, dynamic>;
          final walletId = txData['walletId'];
          final amount = (txData['amount'] ?? 0.0).toDouble();
          final type = txData['type'];

          if (type == 'payout') {
            await _firestore
                .collection('wallets')
                .doc(walletId)
                .update({
                  'pendingBalance': FieldValue.increment(-amount),
                  'updatedAt': Timestamp.now(),
                });
          }
        }
      }
    } catch (e) {
      print('Error updating transaction status: $e');
      rethrow;
    }
  }
}
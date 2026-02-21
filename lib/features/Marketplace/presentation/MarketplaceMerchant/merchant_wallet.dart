import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:vero360_app/GernalServices/firebase_wallet_service.dart';
import 'package:vero360_app/GeneralModels/wallet_model.dart';

class MerchantWalletPage extends StatefulWidget {
  final String merchantId;
  final String merchantName;
  final String serviceType;

  const MerchantWalletPage({
    super.key,
    required this.merchantId,
    required this.merchantName,
    required this.serviceType,
  });

  @override
  State<MerchantWalletPage> createState() => _MerchantWalletPageState();
}

class _MerchantWalletPageState extends State<MerchantWalletPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  WalletModel? _wallet;
  double _walletBalance = 0.0;
  double _pendingBalance = 0.0;
  bool _isLoading = true;
  bool _isProcessingPayout = false;
  List<WalletTransaction> _recentTransactions = [];
  
  final _formKey = GlobalKey<FormState>();
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _amountController = TextEditingController();
  final _phoneController = TextEditingController();
  
  static const List<Map<String, String>> _banks = [
    {"uuid": "82310dd1-ec9b-4fe7-a32c-2f262ef08681", "name": "National Bank of Malawi"},
    {"uuid": "5b9f76b1-620a-4eb9-8848-43d1e3e372dd", "name": "NBS Bank Limited"},
    {"uuid": "87e62436-0553-4fb5-a76d-f27d28420c5b", "name": "Ecobank Malawi Limited"},
    {"uuid": "b064172a-8a1b-4f7f-aad7-81b036c46c57", "name": "FDH Bank Limited"},
    {"uuid": "e7447c2c-c147-4907-b194-e087fe8d8585", "name": "Standard Bank Limited"},
    {"uuid": "236760c9-3045-4a01-990e-497b28d115bb", "name": "Centenary Bank"},
    {"uuid": "968ac588-3b1f-4d89-81ff-a3d43a599003", "name": "First Capital Limited"},
    {"uuid": "c759d7b6-ae5c-4a95-814a-79171271897a", "name": "CDH Investment Bank"},
  ];
  
  static const List<Map<String, String>> _mobileMoneyProviders = [
    {"id": "airtel_money", "name": "Airtel Money"},
    {"id": "mpamba", "name": "MPamba (TNM)"},
    {"id": "national_bank_mobile", "name": "National Bank Mobile"},
  ];
  
  int? _selectedBankIndex;
  String _selectedPayoutMethod = 'bank';
  String _selectedMobileProvider = 'airtel_money';
  
  StreamSubscription<WalletModel?>? _walletSubscription;
  StreamSubscription<QuerySnapshot>? _transactionsSubscription;

  @override
  void initState() {
    super.initState();
    _initializeWallet();
    _loadMerchantData();
  }

  Future<void> _initializeWallet() async {
    try {
      // Get or create wallet
      final wallet = await FirebaseWalletService.getOrCreateWallet(
        merchantId: widget.merchantId,
        merchantName: widget.merchantName,
      );
      
      // Set up real-time wallet stream
      _walletSubscription = FirebaseWalletService
          .getWalletStream(widget.merchantId)
          .listen((wallet) {
        if (wallet != null && mounted) {
          setState(() {
            _wallet = wallet;
            _walletBalance = wallet.balance;
            _pendingBalance = wallet.pendingBalance;
          });
        }
      });
      
      // Set up transactions stream
      _setupTransactionsStream(wallet.walletId);
      
      setState(() {
        _wallet = wallet;
        _walletBalance = wallet.balance;
        _pendingBalance = wallet.pendingBalance;
        _isLoading = false;
      });
    } catch (e) {
      print('Wallet initialization error: $e');
      _showError('Failed to load wallet: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupTransactionsStream(String walletId) {
    _transactionsSubscription = _firestore
        .collection('wallet_transactions')
        .where('walletId', isEqualTo: walletId)
        .where('type', whereIn: ['credit', 'debit', 'payout'])
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _recentTransactions = snapshot.docs.map((doc) {
            final data = doc.data();
            return WalletTransaction.fromMap({
              ...data,
              'transactionId': doc.id,
            });
          }).toList();
        });
      }
    }, onError: (error) {
      print('Transaction stream error: $error');
    });
  }

  Future<void> _loadMerchantData() async {
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(widget.merchantId)
          .get();
      
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _emailController.text = userData['email'] ?? '';
          _phoneController.text = userData['phone'] ?? '';
          
          // Load bank details if available
          if (userData['bankDetails'] != null) {
            final bankDetails = userData['bankDetails'] as Map<String, dynamic>;
            _accountNameController.text = bankDetails['accountName'] ?? '';
            _accountNumberController.text = bankDetails['accountNumber'] ?? '';
          }
        });
      }
    } catch (e) {
      print('Error loading merchant data: $e');
    }
  }

  Future<void> _saveBankDetails() async {
    try {
      await _firestore
          .collection('users')
          .doc(widget.merchantId)
          .update({
            'bankDetails': {
              'accountName': _accountNameController.text.trim(),
              'accountNumber': _accountNumberController.text.trim(),
              'bank': _selectedBankIndex != null 
                  ? _banks[_selectedBankIndex! - 1]['name']
                  : null,
              'updatedAt': FieldValue.serverTimestamp(),
            }
          });
    } catch (e) {
      print('Error saving bank details: $e');
    }
  }

  void _showPayoutDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8A00).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            widget.serviceType.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFFFF8A00),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.merchantName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Request Payout',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF8A00),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Available: MWK ${_walletBalance.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    if (_pendingBalance > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Pending: MWK ${_pendingBalance.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Payout Method Selection
                    const Text(
                      'Payout Method *',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'bank',
                          label: Text('Bank Transfer'),
                          icon: Icon(Icons.account_balance),
                        ),
                        ButtonSegment<String>(
                          value: 'mobile_money',
                          label: Text('Mobile Money'),
                          icon: Icon(Icons.phone_android),
                        ),
                      ],
                      selected: {_selectedPayoutMethod},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _selectedPayoutMethod = newSelection.first;
                        });
                      },
                      style: SegmentedButton.styleFrom(
                        backgroundColor: Colors.grey[100],
                        selectedBackgroundColor: const Color(0xFFFF8A00),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Bank Selection
                    if (_selectedPayoutMethod == 'bank') ...[
                      const Text(
                        'Select Bank *',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedBankIndex,
                        decoration: InputDecoration(
                          labelText: 'Select Bank',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          prefixIcon: const Icon(
                            Icons.account_balance,
                            color: Color(0xFFFF8A00),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                        hint: const Text('Choose your bank'),
                        isExpanded: true,
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: Color(0xFFFF8A00),
                        ),
                        dropdownColor: Colors.white,
                        items: _banks.asMap().entries.map((entry) {
                          int index = entry.key;
                          Map<String, String> bank = entry.value;
                          return DropdownMenuItem<int>(
                            value: index + 1,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.account_balance_outlined,
                                  size: 20,
                                  color: Color(0xFFFF8A00),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    bank['name']!,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedBankIndex = value);
                        },
                        validator: (value) => 
                            value == null ? 'Please select a bank' : null,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Mobile Money Provider Selection
                    if (_selectedPayoutMethod == 'mobile_money') ...[
                      const Text(
                        'Select Provider *',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedMobileProvider,
                        decoration: InputDecoration(
                          labelText: 'Mobile Money Provider',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          prefixIcon: const Icon(
                            Icons.phone_android,
                            color: Color(0xFFFF8A00),
                          ),
                        ),
                        items: _mobileMoneyProviders
                            .map((provider) => DropdownMenuItem<String>(
                                  value: provider['id'],
                                  child: Text(provider['name']!),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() => _selectedMobileProvider = value!);
                        },
                        validator: (value) => 
                            value == null ? 'Please select provider' : null,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Contact Information
                    _buildTextField(
                      controller: _emailController,
                      label: 'Email',
                      icon: Icons.email,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Email is required';
                        if (!value!.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Account/Phone Information
                    if (_selectedPayoutMethod == 'bank')
                      _buildTextField(
                        controller: _accountNameController,
                        label: 'Account Name',
                        icon: Icons.account_box,
                        validator: (value) =>
                            value?.isEmpty ?? true ? 'Account name required' : null,
                      ),
                    
                    if (_selectedPayoutMethod == 'bank') const SizedBox(height: 16),
                    
                    if (_selectedPayoutMethod == 'bank')
                      _buildTextField(
                        controller: _accountNumberController,
                        label: 'Account Number',
                        icon: Icons.credit_card,
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value?.isEmpty ?? true) return 'Account number required';
                          if (value!.length < 8) return 'Enter a valid account number';
                          return null;
                        },
                      ),
                    
                    if (_selectedPayoutMethod == 'mobile_money')
                      _buildTextField(
                        controller: _phoneController,
                        label: 'Mobile Money Number',
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value?.isEmpty ?? true) return 'Phone number required';
                          final phone = value!.replaceAll(' ', '');
                          if (!phone.startsWith('+265')) return 'Enter with +265 prefix';
                          if (phone.length != 13) return 'Enter valid 13-digit number';
                          return null;
                        },
                      ),
                    
                    const SizedBox(height: 16),

                    // Amount
                    _buildTextField(
                      controller: _amountController,
                      label: 'Amount (MWK)',
                      icon: Icons.attach_money,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Please enter amount';
                        final amount = double.tryParse(value!);
                        if (amount == null) return 'Invalid amount';
                        if (amount <= 0) return 'Amount must be greater than 0';
                        if (amount > _walletBalance) return 'Insufficient balance';
                        if (amount < 1000) return 'Minimum withdrawal is MWK 1,000';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Terms and Fees
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFD9B3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.orange),
                              SizedBox(width: 8),
                              Text(
                                'Payout Information',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            '• Processing time: 24-48 hours',
                            style: TextStyle(fontSize: 12),
                          ),
                          Text(
                            '• Minimum withdrawal: MWK 1,000',
                            style: TextStyle(fontSize: 12),
                          ),
                          Text(
                            '• Transaction fees: 1% (min MWK 100)',
                            style: TextStyle(fontSize: 12),
                          ),
                          Text(
                            '• Funds will be sent to your registered account',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              _clearControllers();
                              Navigator.pop(context);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isProcessingPayout
                                ? null
                                : () => _requestPayout(setState),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF8A00),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isProcessingPayout
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text('Submit Request'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFFFF8A00)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF8A00)),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  void _clearControllers() {
    _accountNameController.clear();
    _accountNumberController.clear();
    _amountController.clear();
    _selectedBankIndex = null;
  }

  Future<void> _requestPayout(void Function(void Function()) setState) async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedPayoutMethod == 'bank' && _selectedBankIndex == null) {
      _showError('Please select a bank');
      return;
    }

    setState(() => _isProcessingPayout = true);
    
    try {
      final amount = double.parse(_amountController.text);
      final payoutRef = 'PAYOUT-${widget.serviceType}-${DateTime.now().millisecondsSinceEpoch}';
      
      // Calculate fee (1% minimum MWK 100)
      final fee = (amount * 0.01).clamp(100.0, amount);
      final netAmount = amount - fee;
      
      // 1. Debit wallet in Firestore
      await FirebaseWalletService.debitWallet(
        merchantId: widget.merchantId,
        amount: amount,
        description: _selectedPayoutMethod == 'bank' 
            ? 'Bank Transfer Payout (${widget.serviceType})' 
            : '${_selectedMobileProvider.toUpperCase()} Payout (${widget.serviceType})',
        reference: payoutRef,
      );
      
      // 2. Save bank details for future use
      if (_selectedPayoutMethod == 'bank') {
        await _saveBankDetails();
      }
      
      // 3. Show success and close dialog
      if (mounted) {
        Navigator.pop(context);
        _showSuccess('Payout request submitted! Processing in 24-48 hours.');
      }
      _clearControllers();
      
    } catch (e) {
      print('Payout error: $e');
      _showError('Failed to process payout: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayout = false);
      }
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showTransactionDetails(WalletTransaction transaction) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Transaction Details'),
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
                  color: transaction.type == 'credit' ? Colors.green : Colors.orange,
                ),
                title: Text(
                  transaction.description,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  DateFormat('MMM dd, yyyy HH:mm').format(transaction.createdAt),
                ),
              ),
              Divider(),
              DetailRow('Amount', 'MWK ${transaction.amount.toStringAsFixed(2)}'),
              DetailRow('Type', transaction.type.toUpperCase()),
              DetailRow('Status', transaction.status.toUpperCase()),
              DetailRow('Reference', transaction.reference),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget DetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.serviceType.toUpperCase()} Wallet',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF16284C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8A00)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Balance Card
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF16284C), Color(0xFFFF8A00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF8A00).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Available Balance',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.account_balance_wallet,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.merchantName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'MWK ${NumberFormat('#,##0.00').format(_walletBalance)}',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (_pendingBalance > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Pending: MWK ${_pendingBalance.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _walletBalance >= 1000
                                ? _showPayoutDialog
                                : null,
                            icon: const Icon(Icons.payment),
                            label: const Text('Request Payout'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: const Color(0xFFFF8A00),
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  
                  // Recent Transactions Header
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Recent Transactions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Transactions List
                  if (_recentTransactions.isEmpty)
                    _buildEmptyCard()
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _recentTransactions.length,
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () => _showTransactionDetails(_recentTransactions[index]),
                          child: _buildTransactionCard(_recentTransactions[index]),
                        );
                      },
                    ),

                  const SizedBox(height: 16),
                  
                  // View All Transactions Button
                  Center(
                    child: TextButton(
                      onPressed: () {
                        // Navigate to full transactions page
                      },
                      child: const Text(
                        'View All Transactions',
                        style: TextStyle(color: Color(0xFFFF8A00)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Icon(Icons.history, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your transaction history will appear here',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(WalletTransaction transaction) {
    Color statusColor;
    IconData statusIcon;
    String statusText = transaction.status;
    
    switch (transaction.status.toLowerCase()) {
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
    
    final isCredit = transaction.type.toLowerCase() == 'credit';
    final amountPrefix = isCredit ? '+' : '-';
    final amountColor = isCredit ? Colors.green : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        title: Row(
          children: [
            Expanded(
              child: Text(
                transaction.description,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$amountPrefix MWK ${transaction.amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: amountColor,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(statusIcon, size: 16, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  statusText.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('MMM dd, HH:mm').format(transaction.createdAt),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            if (transaction.reference.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Ref: ${transaction.reference}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
      ),
    );
  }

  @override
  void dispose() {
    _walletSubscription?.cancel();
    _transactionsSubscription?.cancel();
    _accountNameController.dispose();
    _accountNumberController.dispose();
    _emailController.dispose();
    _amountController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
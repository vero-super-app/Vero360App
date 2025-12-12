import 'package:flutter/material.dart';
import 'package:intl/intl.dart';


import 'package:vero360_app/models/mybooking_model.dart';

import 'package:vero360_app/services/mybooking_service.dart';
import 'package:vero360_app/toasthelper.dart';

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({Key? key}) : super(key: key);

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> with SingleTickerProviderStateMixin {
  final _svc = MyBookingService();
  final Color _brand = const Color(0xFFFF8A00);
  final _money = NumberFormat.currency(symbol: 'MK ', decimalDigits: 0);
  final _date  = DateFormat('dd MMM yyyy');

  late TabController _tab;
  late Future<List<BookingItem>> _future;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _future = _svc.getMyBookings();
  }

  Future<void> _reload() async {
    setState(() => _future = _svc.getMyBookings());
    await _future;
  }

  // Classification:
  bool _isCancelled(BookingItem b) => b.status == BookingStatus.cancelled;
  bool _isPast(BookingItem b) {
    if (b.status == BookingStatus.completed) return true;
    if (b.bookingDate != null) {
      return b.bookingDate!.isBefore(DateTime.now());
    }
    return false;
  }
  bool _isActive(BookingItem b) => !_isCancelled(b) && !_isPast(b);

  Color _statusColor(BookingStatus s) {
    switch (s) {
      case BookingStatus.pending:   return _brand;
      case BookingStatus.confirmed: return Colors.blueAccent;
      case BookingStatus.cancelled: return Colors.redAccent;
      case BookingStatus.completed: return Colors.green;
      case BookingStatus.unknown:   return Colors.grey;
    }
  }

  String _statusLabel(BookingStatus s) {
    switch (s) {
      case BookingStatus.pending:   return 'Pending';
      case BookingStatus.confirmed: return 'Confirmed';
      case BookingStatus.cancelled: return 'Cancelled';
      case BookingStatus.completed: return 'Completed';
      case BookingStatus.unknown:   return '—';
    }
  }

  Widget _chip(Color c, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: .35)),
      ),
      child: Text(
        text,
        style: TextStyle(color: c.withValues(alpha: .95), fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _cancel(BookingItem b) async {
    try {
      final moved = await _svc.cancelOrDelete(b.id);
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        moved ? 'Booking moved to Cancelled' : 'Booking cancelled (removed)',
        isSuccess: true,
        errorMessage: '',
      );
      await _reload();
      if (moved) _tab.animateTo(1); // jump to Cancelled tab
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Cancel failed', isSuccess: false, errorMessage: e.toString());
    }
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6B778C)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFF6B778C)),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  Widget _card(BookingItem b) {
    final locType = [
      if ((b.accommodationLocation ?? '').isNotEmpty) b.accommodationLocation!,
      if ((b.accommodationType ?? '').isNotEmpty) b.accommodationType!,
    ].join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            blurRadius: 22,
            spreadRadius: -8,
            offset: Offset(0, 14),
            color: Color(0x1A000000),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 82,
              height: 82,
              child: (b.imageUrl == null || b.imageUrl!.isEmpty)
                  ? Container(
                      color: const Color(0xFFF1F2F6),
                      child: const Icon(Icons.hotel_outlined, color: Colors.grey),
                    )
                  : Image.network(b.imageUrl!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + chips
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        b.accommodationName ?? 'Accommodation',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF222222),
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _chip(_statusColor(b.status), _statusLabel(b.status)),
                        const SizedBox(height: 6),
                        _chip(_brand, _money.format(b.total)),
                      ],
                    )
                  ],
                ),

                const SizedBox(height: 8),
                _infoRow(Icons.place_outlined, locType.isEmpty ? '—' : locType),

                const SizedBox(height: 6),
                if (b.bookingDate != null)
                  _infoRow(Icons.schedule_outlined, _date.format(b.bookingDate!.toLocal())),

                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      'Price: ${_money.format(b.price)}  •  Fee: ${_money.format(b.bookingFee)}',
                      style: const TextStyle(
                        color: Color(0xFF222222),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (_isActive(b))
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _brand,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _cancel(b),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBody(List<BookingItem> data, bool Function(BookingItem) predicate, String emptyText) {
    final items = data.where(predicate).toList();
    if (items.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 90),
          Center(child: Text('No bookings available', style: TextStyle(color: Colors.red))),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: items.length,
      itemBuilder: (_, i) => _card(items[i]),
    );
  }

  Future<void> _openCreate() async {
    final created = await showModalBottomSheet<BookingItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BookingFormSheet(onSubmit: (p) => _svc.createBooking(p)),
    );
    if (created != null) {
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Booking created', isSuccess: true, errorMessage: '');
      await _reload();
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF222222),
        title: const Text('My Bookings'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tab,
          labelColor: _brand,
          unselectedLabelColor: const Color(0xFF6B778C),
          indicatorColor: _brand,
          tabs: const [
            Tab(text: 'My Bookings'),
            Tab(text: 'Cancelled'),
            Tab(text: 'History'),
          ],
        ),
      ),
      
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<BookingItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Error: ${snap.error}', textAlign: TextAlign.center),
                    ),
                  ),
                ],
              );
            }
            final data = snap.data ?? const <BookingItem>[];
            return TabBarView(
              controller: _tab,
              children: [
                _tabBody(data, _isActive, 'No active bookings'),
                _tabBody(data, _isCancelled, 'No cancelled bookings'),
                _tabBody(data, _isPast, 'No History bookings'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class BookingFormSheet extends StatefulWidget {
  const BookingFormSheet({Key? key, required this.onSubmit}) : super(key: key);
  final Future<BookingItem> Function(BookingCreatePayload) onSubmit;

  @override
  State<BookingFormSheet> createState() => _BookingFormSheetState();
}

class _BookingFormSheetState extends State<BookingFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _accIdCtrl = TextEditingController();
  final _dateCtrl  = TextEditingController();
  final _priceCtrl = TextEditingController(text: '49990');
  final _feeCtrl   = TextEditingController(text: '5000');

  bool _saving = false;

  @override
  void dispose() {
    _accIdCtrl.dispose();
    _dateCtrl.dispose();
    _priceCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      _dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
      setState((){});
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final payload = BookingCreatePayload(
        accommodationId: int.parse(_accIdCtrl.text.trim()),
        bookingDate: _dateCtrl.text.trim(),
        price: num.parse(_priceCtrl.text.trim()),
        bookingFee: num.parse(_feeCtrl.text.trim()),
      );
      final created = await widget.onSubmit(payload);
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Failed to create booking', isSuccess: false, errorMessage: e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = const Color(0xFFFF8A00);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('New Booking', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _accIdCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Accommodation ID',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n <= 0) return 'Enter a valid accommodationId';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _dateCtrl,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Booking Date',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.event),
                          onPressed: _pickDate,
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Choose a date' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Price',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || num.tryParse(v) == null) ? 'Enter price' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _feeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Booking Fee',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || num.tryParse(v) == null) ? 'Enter fee' : null,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: brand,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Saving…' : 'Create Booking'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

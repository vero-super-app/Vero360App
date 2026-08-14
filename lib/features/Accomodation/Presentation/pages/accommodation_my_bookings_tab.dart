import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/my_Accodation_bookingdata_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/guest_booking_local_cache.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/mybookingData_service.dart'
    show AuthRequiredException, MyBookingService;
import 'package:vero360_app/features/Accomodation/Presentation/widgets/booking_delete_confirm_dialog.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/GernalServices/order_escrow_service.dart';
import 'package:vero360_app/utils/app_wallet_pin.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// Lists the signed-in user’s accommodation bookings from `GET /vero/bookings/me`.
class AccommodationMyBookingsTab extends StatefulWidget {
  final bool isDark;

  const AccommodationMyBookingsTab({super.key, required this.isDark});

  @override
  State<AccommodationMyBookingsTab> createState() =>
      AccommodationMyBookingsTabState();
}

class AccommodationMyBookingsTabState extends State<AccommodationMyBookingsTab>
    with AutomaticKeepAliveClientMixin {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  final MyBookingService _svc = MyBookingService();
  Future<List<BookingItem>>? _future;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  DateTime? _searchDate;

  /// Escrow snapshot keyed by booking id / booking number.
  final Map<String, OrderEscrowSnapshot?> _escrowByBooking = {};
  String? _releasingBookingKey;
  String _accountPhone = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  void reload() => _reload();

  Future<List<BookingItem>> _load() async {
    final loggedIn = await AuthHandler.isAuthenticated();
    if (!loggedIn) {
      // Avoid showing a previous account’s cached stays while signed out.
      await GuestBookingLocalCache.clearOnLogout();
      throw AuthRequiredException('Sign in to see your bookings');
    }
    try {
      final sp = await SharedPreferences.getInstance();
      _accountPhone = (sp.getString('phone') ?? '').trim();
    } catch (_) {}
    final list = await _svc.getGuestMyBookings();
    await _loadEscrowForBookings(list);
    return list;
  }

  String _bookerPhone(BookingItem b) {
    final p = (b.guestPhone ?? '').trim();
    if (p.isNotEmpty) return p;
    return _accountPhone;
  }

  String _bookingEscrowKey(BookingItem b) {
    final bn = (b.bookingNumber ?? '').trim();
    if (bn.isNotEmpty) return bn;
    return b.id.trim();
  }

  Future<void> _loadEscrowForBookings(
    List<BookingItem> list, {
    bool notify = false,
  }) async {
    final next = <String, OrderEscrowSnapshot?>{};
    await Future.wait(list.map((b) async {
      if (!b.includeInGuestMyBookings &&
          b.status != BookingStatus.confirmed &&
          b.status != BookingStatus.completed) {
        return;
      }
      final key = _bookingEscrowKey(b);
      if (key.isEmpty) return;
      try {
        next[key] = await OrderEscrowService.fetchEscrowForAccommodationBooking(
          bookingId: b.id,
          bookingNumber: b.bookingNumber ?? b.displayBookingRef,
        );
      } catch (_) {
        next[key] = null;
      }
    }));
    _escrowByBooking
      ..clear()
      ..addAll(next);
    if (notify && mounted) setState(() {});
  }

  bool _isOnOrAfterCheckIn(BookingItem b) {
    final start = b.bookingDate;
    if (start == null) return true;
    final today = DateTime.now();
    final checkIn = DateTime(start.year, start.month, start.day);
    final d = DateTime(today.year, today.month, today.day);
    return !d.isBefore(checkIn);
  }

  Future<void> _confirmArrivalAndRelease(BookingItem b) async {
    final key = _bookingEscrowKey(b);
    if (key.isEmpty || _releasingBookingKey != null) return;

    var escrow = _escrowByBooking[key] ??
        await OrderEscrowService.fetchEscrowForAccommodationBooking(
          bookingId: b.id,
          bookingNumber: b.bookingNumber ?? b.displayBookingRef,
        );
    if (!mounted) return;
    if (escrow == null || !escrow.isHeld) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No payment is on hold for this stay (already released or missing).',
          ),
        ),
      );
      return;
    }

    if (!_isOnOrAfterCheckIn(b)) {
      final when = b.bookingDate != null
          ? DateFormat.yMMMd().format(b.bookingDate!)
          : 'check-in day';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You can confirm arrival from $when (check-in day) onward.',
          ),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Confirm arrival?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          'By confirming, you are telling us you have arrived at '
          '${(b.accommodationName ?? 'this stay').trim()}.\n\n'
          'This will release the held payment from escrow to the '
          'accommodation owner.\n\n'
          'If you confirm without actually going to the accommodation, '
          'Vero360 is not responsible for that payment.\n\n'
          'Next, you will verify with biometrics or your wallet password.',
          style: TextStyle(height: 1.45, color: Colors.grey.shade800),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _brandOrange),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _releasingBookingKey = key);
    try {
      final verified = await AppWalletPin.verifyStayArrival(context);
      if (!verified || !mounted) return;

      await OrderEscrowService.releaseFunds(
        orderId: escrow.orderId,
        buyerConfirmed: true,
      );
      if (!mounted) return;

      ToastHelper.showCustomToast(
        context,
        'Payment released to the host. Enjoy your stay!',
        isSuccess: true,
        errorMessage: '',
      );

      final refreshed =
          await OrderEscrowService.fetchEscrowForAccommodationBooking(
        bookingId: b.id,
        bookingNumber: b.bookingNumber ?? b.displayBookingRef,
      );
      if (!mounted) return;
      setState(() => _escrowByBooking[key] = refreshed);
    } on StateError catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        e.toString().replaceFirst('Bad state: ', ''),
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not release payment: $e',
        isSuccess: false,
        errorMessage: '$e',
      );
    } finally {
      if (mounted) setState(() => _releasingBookingKey = null);
    }
  }

  Widget _buildEscrowReleaseSection(BookingItem b) {
    if (!b.includeInGuestMyBookings &&
        b.status != BookingStatus.confirmed &&
        b.status != BookingStatus.completed) {
      return const SizedBox.shrink();
    }

    final key = _bookingEscrowKey(b);
    final escrow = _escrowByBooking[key];
    final releasing = _releasingBookingKey == key;

    if (escrow != null && escrow.isReleased) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_rounded, color: Colors.green.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Arrival confirmed — payment released to the host.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.green.shade900,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (escrow == null || !escrow.isHeld) {
      return const SizedBox.shrink();
    }

    final canConfirm = _isOnOrAfterCheckIn(b);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _brandOrange.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment held in escrow',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: _brandNavy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              canConfirm
                  ? 'When you arrive at your stay, confirm below to release payment to the host. This uses Face ID / fingerprint or your wallet password.'                  : 'After check-in day, confirm arrival here to release the held payment to the host.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (!canConfirm || releasing)
                    ? null
                    : () => _confirmArrivalAndRelease(b),
                icon: releasing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.home_work_rounded, size: 20),
                label: Text(
                  releasing
                      ? 'Releasing…'
                      : canConfirm
                          ? 'I\'ve arrived — release payment'
                          : 'Available on check-in day',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _brandOrange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _showPaidBadge(BookingItem b) {
    if (b.includeInGuestMyBookings) return true;
    switch (b.status) {
      case BookingStatus.confirmed:
      case BookingStatus.completed:
        return true;
      case BookingStatus.pending:
      case BookingStatus.cancelled:
      case BookingStatus.unknown:
        return false;
    }
  }

  String _statusLabel(BookingItem b) {
    if (b.includeInGuestMyBookings &&
        (b.status == BookingStatus.pending ||
            b.status == BookingStatus.unknown)) {
      return 'Booked';
    }
    switch (b.status) {
      case BookingStatus.pending:
        return 'Pending payment';
      case BookingStatus.confirmed:
      case BookingStatus.completed:
        return 'Booked';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.unknown:
        return b.includeInGuestMyBookings ? 'Booked' : 'Status unknown';
    }
  }

  String _normalizeSearchText(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _matchesBookingSearch(BookingItem b, DateFormat dateFmt) {
    if (_searchDate != null) {
      final d = b.bookingDate;
      if (d == null ||
          d.year != _searchDate!.year ||
          d.month != _searchDate!.month ||
          d.day != _searchDate!.day) {
        return false;
      }
    }
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.trim().toLowerCase();
    final qCompact = _normalizeSearchText(q);

    final fields = <String>[
      b.displayBookingRef,
      b.bookingNumber ?? '',
      b.id,
      b.accommodationName ?? '',
      b.accommodationLocation ?? '',
      b.guestName ?? '',
      b.guestEmail ?? '',
      b.guestPhone ?? '',
      _bookerPhone(b),
      if (b.bookingDate != null) dateFmt.format(b.bookingDate!),
      if (b.bookingDate != null) DateFormat('yyyy-MM-dd').format(b.bookingDate!),
      if (b.bookingDate != null) formatStayReceiptDate(b.bookingDate),
      if (b.transactionDate != null) formatStayReceiptDate(b.transactionDate),
    ];

    for (final f in fields) {
      final raw = f.trim().toLowerCase();
      if (raw.isEmpty) continue;
      if (raw.contains(q)) return true;
      if (qCompact.isNotEmpty && _normalizeSearchText(raw).contains(qCompact)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _pickSearchDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _searchDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() => _searchDate = DateTime(picked.year, picked.month, picked.day));
  }

  bool _hasBookerDetails(BookingItem b) {
    return (b.guestName ?? '').trim().isNotEmpty ||
        (b.guestEmail ?? '').trim().isNotEmpty ||
        _bookerPhone(b).isNotEmpty;
  }

  Future<void> _confirmAndDelete(BuildContext context, BookingItem b) async {
    if (b.id.isEmpty && (b.bookingNumber ?? '').trim().isEmpty) return;
    final ok = await showBookingDeleteConfirmDialog(
      context,
      bookingId: b.id.isNotEmpty ? b.id : (b.bookingNumber ?? ''),
      bookingRefLabel: b.displayBookingRef,
      title: 'Delete this booking?',
      body:
          'This removes the booking from your account. This action cannot be undone.',
    );
    if (ok != true || !context.mounted) return;
    try {
      var removedFromServer = false;
      final id = b.id.trim();
      if (id.isNotEmpty) {
        try {
          await _svc.deleteBooking(id);
          removedFromServer = true;
        } catch (e) {
          final msg = e.toString().toLowerCase();
          // Cache-only / already-gone rows still need to leave the list.
          final notFound = msg.contains('404') ||
              msg.contains('not found') ||
              msg.contains('notfound');
          if (!notFound) rethrow;
        }
      }
      await GuestBookingLocalCache.removeStay(b);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removedFromServer
                ? 'Booking deleted'
                : 'Booking removed from My bookings',
          ),
        ),
      );
      _reload();
    } catch (e) {
      // Still drop local ghost stays so the UI matches reality.
      try {
        await GuestBookingLocalCache.removeStay(b);
      } catch (_) {}
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currency = NumberFormat('#,##0', 'en');
    final dateFmt = DateFormat.yMMMd();

    return FutureBuilder<List<BookingItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: _brandOrange),
            ),
          );
        }

        if (snapshot.hasError) {
          final err = snapshot.error;
          final msg = err.toString();
          final needAuth = err is AuthRequiredException ||
              msg.contains('401') ||
              msg.contains('Unauthorized') ||
              msg.contains('No auth token');
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: Colors.grey.shade500),
              const SizedBox(height: 12),
              Text(
                needAuth ? 'Sign in to see your bookings' : 'Could not load bookings',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: _brandNavy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                needAuth
                    ? 'Your stay bookings appear here after you book and pay.'
                    : msg.replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, height: 1.35),
              ),
              if (needAuth) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Sign in'),
                ),
              ],
            ],
          );
        }

        final list = snapshot.data ?? [];
        final filtered = list.where((b) => _matchesBookingSearch(b, dateFmt)).toList();
        if (list.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.hotel_outlined, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No bookings yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: _brandNavy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Only stays with successful payment appear here. After checkout completes, pull to refresh if needed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );
        }

        return RefreshIndicator(
          color: _brandOrange,
          onRefresh: () async {
            _reload();
            await _future;
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: filtered.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E6EF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Search bookings',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _brandNavy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Booking ref, name or booking date',
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF7F8FB),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _pickSearchDate(context),
                            icon: const Icon(Icons.event_rounded, size: 18),
                            label: Text(
                              _searchDate == null
                                  ? 'Filter by date'
                                  : dateFmt.format(_searchDate!),
                            ),
                          ),
                          if (_searchDate != null || _searchQuery.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _searchDate = null;
                                });
                              },
                              child: const Text('Clear'),
                            ),
                          ],
                        ],
                      ),
                      if (filtered.isEmpty)
                        Text(
                          'No bookings match this search.',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                );
              }
              final b = filtered[index - 1];
              final title = (b.accommodationName ?? 'Accommodation').trim();
              final loc = (b.accommodationLocation ?? '').trim();
              final paid = _showPaidBadge(b);
              final when = formatStayReceiptDate(b.bookingDate);
              final txWhen = formatStayReceiptDate(
                b.transactionDate ?? b.bookingDate,
              );
              final phone = _bookerPhone(b);

              return Material(
                color: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
                elevation: 0,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: widget.isDark
                          ? Colors.white12
                          : const Color(0xFFE2E6EF),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((b.imageUrl ?? '').trim().isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  b.imageUrl!.trim(),
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              )
                            else
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: _brandOrange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.apartment_rounded,
                                    color: _brandOrange, size: 32),
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      color: widget.isDark
                                          ? Colors.white
                                          : _brandNavy,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (loc.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      loc,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: widget.isDark
                                            ? Colors.white70
                                            : Colors.grey.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (_hasBookerDetails(b)) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Booked by',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    if ((b.guestName ?? '').trim().isNotEmpty)
                                      Text(
                                        b.guestName!.trim(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: widget.isDark
                                              ? Colors.white70
                                              : Colors.grey.shade800,
                                        ),
                                      ),
                                    if ((b.guestEmail ?? '').trim().isNotEmpty)
                                      Text(
                                        b.guestEmail!.trim(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: widget.isDark
                                              ? Colors.white54
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                    if (phone.isNotEmpty)
                                      Text(
                                        phone,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: widget.isDark
                                              ? Colors.white54
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete booking',
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: b.id.isEmpty
                                    ? Colors.grey
                                    : Colors.red.shade400,
                              ),
                              onPressed: b.id.isEmpty
                                  ? null
                                  : () => _confirmAndDelete(context, b),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (paid)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.green.shade200,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.paid_rounded,
                                        size: 16,
                                        color: Colors.green.shade800),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Paid',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _brandOrange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _statusLabel(b),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  color: _brandOrange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 22),
                        if ((b.guestName ?? '').trim().isNotEmpty ||
                            (b.guestEmail ?? '').trim().isNotEmpty) ...[
                          _detailRow(
                            Icons.person_outline_rounded,
                            'Guest / booker',
                            [
                              if ((b.guestName ?? '').trim().isNotEmpty)
                                b.guestName!.trim(),
                              if ((b.guestEmail ?? '').trim().isNotEmpty)
                                b.guestEmail!.trim(),
                            ].join('\n'),
                            widget.isDark,
                          ),
                          const SizedBox(height: 8),
                        ],
                        _detailRow(
                          Icons.phone_iphone_rounded,
                          'Booker phone',
                          phone.isNotEmpty ? phone : '—',
                          widget.isDark,
                        ),
                        const SizedBox(height: 8),
                        _detailRow(
                          Icons.event_rounded,
                          'Check-in',
                          when,
                          widget.isDark,
                        ),
                        const SizedBox(height: 8),
                        _detailRow(
                          Icons.receipt_long_rounded,
                          'Transaction date',
                          txWhen,
                          widget.isDark,
                        ),
                        const SizedBox(height: 8),
                        _detailRow(
                          Icons.tag_rounded,
                          'Booking ref',
                          b.displayBookingRef.isNotEmpty
                              ? b.displayBookingRef
                              : '—',
                          widget.isDark,
                          trailing: b.displayBookingRef.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Copy booking ref',
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: b.displayBookingRef),
                                    );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Booking ref copied'),
                                      ),
                                    );
                                  },
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        _detailRow(
                          Icons.payments_outlined,
                          'Total',
                          'MWK ${currency.format(b.total.round())}',
                          widget.isDark,
                          boldValue: true,
                        ),
                        _buildEscrowReleaseSection(b),
                        if (b.accommodationId != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Property ID: ${b.accommodationId}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value,
    bool isDark, {
    bool boldValue = false,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: boldValue ? FontWeight.w900 : FontWeight.w700,
                  color: isDark ? Colors.white : _brandNavy,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }
}

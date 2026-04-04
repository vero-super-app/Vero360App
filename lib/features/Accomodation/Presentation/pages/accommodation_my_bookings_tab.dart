import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/my_Accodation_bookingdata_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/mybookingData_service.dart'
    show AuthRequiredException, MyBookingService;
import 'package:vero360_app/features/Accomodation/Presentation/widgets/booking_delete_confirm_dialog.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';

/// Lists the signed-in user’s accommodation bookings from `GET /vero/bookings/me`.
class AccommodationMyBookingsTab extends StatefulWidget {
  final bool isDark;

  const AccommodationMyBookingsTab({super.key, required this.isDark});

  @override
  State<AccommodationMyBookingsTab> createState() =>
      _AccommodationMyBookingsTabState();
}

class _AccommodationMyBookingsTabState extends State<AccommodationMyBookingsTab>
    with AutomaticKeepAliveClientMixin {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  final MyBookingService _svc = MyBookingService();
  Future<List<BookingItem>>? _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<List<BookingItem>> _load() async {
    final loggedIn = await AuthHandler.isAuthenticated();
    if (!loggedIn) {
      throw AuthRequiredException('Sign in to see your bookings');
    }
    return _svc.getMyBookings();
  }

  bool _showPaidBadge(BookingItem b) {
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
    switch (b.status) {
      case BookingStatus.pending:
        return 'Pending payment';
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.unknown:
        return 'Status unknown';
    }
  }

  bool _hasBookerDetails(BookingItem b) {
    return (b.guestName ?? '').trim().isNotEmpty ||
        (b.guestEmail ?? '').trim().isNotEmpty ||
        (b.guestPhone ?? '').trim().isNotEmpty;
  }

  Future<void> _confirmAndDelete(BuildContext context, BookingItem b) async {
    if (b.id.isEmpty) return;
    final ok = await showBookingDeleteConfirmDialog(
      context,
      bookingId: b.id,
      bookingRefLabel: b.displayBookingRef,
      title: 'Delete this booking?',
      body:
          'This removes the booking from your account. This action cannot be undone.',
    );
    if (ok != true || !context.mounted) return;
    try {
      await _svc.deleteBooking(b.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking deleted')),
      );
      _reload();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
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
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final b = list[index];
              final title = (b.accommodationName ?? 'Accommodation').trim();
              final loc = (b.accommodationLocation ?? '').trim();
              final paid = _showPaidBadge(b);
              final when = b.bookingDate != null
                  ? dateFmt.format(b.bookingDate!)
                  : '—';

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
                                    if ((b.guestPhone ?? '').trim().isNotEmpty)
                                      Text(
                                        b.guestPhone!.trim(),
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
                        if (_hasBookerDetails(b)) ...[
                          _detailRow(
                            Icons.person_outline_rounded,
                            'Guest / booker',
                            [
                              if ((b.guestName ?? '').trim().isNotEmpty)
                                b.guestName!.trim(),
                              if ((b.guestEmail ?? '').trim().isNotEmpty)
                                b.guestEmail!.trim(),
                              if ((b.guestPhone ?? '').trim().isNotEmpty)
                                b.guestPhone!.trim(),
                            ].join('\n'),
                            widget.isDark,
                          ),
                          const SizedBox(height: 8),
                        ],
                        _detailRow(
                          Icons.event_rounded,
                          'Check-in / booking date',
                          when,
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
                        ),
                        const SizedBox(height: 8),
                        _detailRow(
                          Icons.payments_outlined,
                          'Total',
                          'MWK ${currency.format(b.total.round())}',
                          widget.isDark,
                          boldValue: true,
                        ),
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
      ],
    );
  }
}

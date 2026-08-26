import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/accommodation_occupancy_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// Host blocks calendar dates for walk-in / phone / offline bookings.
Future<void> showAccommodationOfflineBlockSheet(
  BuildContext context, {
  required String propertyName,
  required int accommodationId,
  required String accommodationType,
  required int capacity,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _OfflineBlockSheet(
      propertyName: propertyName,
      accommodationId: accommodationId,
      accommodationType: accommodationType,
      capacity: capacity,
    ),
  );
}

class _OfflineBlockSheet extends StatefulWidget {
  final String propertyName;
  final int accommodationId;
  final String accommodationType;
  final int capacity;

  const _OfflineBlockSheet({
    required this.propertyName,
    required this.accommodationId,
    required this.accommodationType,
    required this.capacity,
  });

  @override
  State<_OfflineBlockSheet> createState() => _OfflineBlockSheetState();
}

class _OfflineBlockSheetState extends State<_OfflineBlockSheet> {
  static const _orange = Color(0xFFFF8A00);
  static const _navy = Color(0xFF16284C);

  final _occupancy = AccommodationOccupancyService();
  final _guestCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _dateFmt = DateFormat('EEE, d MMM yyyy');

  DateTime _checkIn = DateTime.now();
  DateTime _checkOut = DateTime.now().add(const Duration(days: 1));
  int _rooms = 1;
  bool _loading = true;
  bool _submitting = false;
  List<AccommodationOccupancyStay> _stays = const [];
  Map<String, int> _nightCounts = const {};

  int get _inventoryCapacity =>
      AccommodationOccupancyService.capacityForType(
        accommodationType: widget.accommodationType,
        roomsAvailable: widget.capacity,
      );

  bool get _multiRoom =>
      widget.accommodationType.toLowerCase() == 'hotel' ||
      widget.accommodationType.toLowerCase() == 'lodge';

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _checkIn = DateTime(today.year, today.month, today.day);
    _checkOut = _checkIn.add(const Duration(days: 1));
    _rooms = 1;
    unawaited(_reload());
  }

  @override
  void dispose() {
    _guestCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final staysFuture =
          _occupancy.fetchActiveStays(widget.accommodationId);
      final countsFuture = _occupancy.fetchNightCounts(
        widget.accommodationId,
        fromServer: true,
        prune: true,
      );
      final stays = await staysFuture;
      final counts = await countsFuture;
      if (!mounted) return;
      setState(() {
        _stays = stays;
        _nightCounts = counts;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCheckIn() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkIn.isBefore(first) ? first : _checkIn,
      firstDate: first,
      lastDate: first.add(const Duration(days: 365 * 2)),
      helpText: 'Offline stay — check-in',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _checkIn = DateTime(picked.year, picked.month, picked.day);
      if (!_checkOut.isAfter(_checkIn)) {
        _checkOut = _checkIn.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _pickCheckOut() async {
    final minOut = _checkIn.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkOut.isBefore(minOut) ? minOut : _checkOut,
      firstDate: minOut,
      lastDate: _checkIn.add(const Duration(days: 365 * 2)),
      helpText: 'Offline stay — check-out',
    );
    if (picked == null || !mounted) return;
    setState(
      () => _checkOut = DateTime(picked.year, picked.month, picked.day),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_checkOut.isAfter(_checkIn)) {
      ToastHelper.showCustomToast(
        context,
        'Check-out must be after check-in.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    if (!_occupancy.isRangeAvailable(
      nightCounts: _nightCounts,
      checkIn: _checkIn,
      checkOut: _checkOut,
      capacity: _inventoryCapacity,
      rooms: _rooms,
    )) {
      ToastHelper.showCustomToast(
        context,
        'Some of those nights are already booked on the app calendar.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _occupancy.blockOfflineStay(
        accommodationId: widget.accommodationId,
        checkIn: _checkIn,
        checkOut: _checkOut,
        capacity: _inventoryCapacity,
        rooms: _rooms,
        guestLabel: _guestCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Dates blocked — guests cannot book these nights on Vero.',
        isSuccess: true,
        errorMessage: '',
      );
      _guestCtrl.clear();
      _noteCtrl.clear();
      await _reload();
    } on OccupancyConflictException catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        e.message,
        isSuccess: false,
        errorMessage: '',
      );
    } catch (_) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not block dates. Try again.',
        isSuccess: false,
        errorMessage: '',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _removeBlock(AccommodationOccupancyStay stay) async {
    if (!stay.isOffline) {
      ToastHelper.showCustomToast(
        context,
        'App bookings are managed under Bookings.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove offline block?'),
        content: Text(
          'Free ${_dateFmt.format(stay.checkIn)} → ${_dateFmt.format(stay.checkOut)} '
          'so guests can book on Vero again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _orange),
            child: const Text('Remove block'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _occupancy.releaseOfflineBlock(
        accommodationId: widget.accommodationId,
        bookingRef: stay.bookingRef,
      );
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Dates are open for app bookings again.',
        isSuccess: true,
        errorMessage: '',
      );
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not remove block. Try again.',
        isSuccess: false,
        errorMessage: '',
      );
    }
  }

  Widget _dateTile({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _dateFmt.format(value),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: _navy,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.calendar_month_rounded, color: _orange.withValues(alpha: 0.9)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final offlineStays = _stays.where((s) => s.isOffline).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Block dates (offline booking)',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: _navy,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.propertyName,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'When someone books you directly (walk-in, phone, WhatsApp), '
                    'block those nights here so the same dates cannot be booked on Vero.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: _navy.withValues(alpha: 0.88),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _dateTile(
                        label: 'Check-in',
                        value: _checkIn,
                        onTap: _submitting ? () {} : _pickCheckIn,
                      ),
                      const SizedBox(height: 10),
                      _dateTile(
                        label: 'Check-out',
                        value: _checkOut,
                        onTap: _submitting ? () {} : _pickCheckOut,
                      ),
                      if (_multiRoom && _inventoryCapacity > 1) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Rooms to block',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _submitting || _rooms <= 1
                                  ? null
                                  : () => setState(() => _rooms--),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(
                              '$_rooms / $_inventoryCapacity',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            IconButton(
                              onPressed: _submitting || _rooms >= _inventoryCapacity
                                  ? null
                                  : () => setState(() => _rooms++),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: _guestCtrl,
                        enabled: !_submitting,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Guest name (optional)',
                          hintText: 'e.g. John — walk-in',
                          filled: true,
                          fillColor: const Color(0xFFF7F8FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _noteCtrl,
                        enabled: !_submitting,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: 'Note (optional)',
                          hintText: 'Phone booking, agency, etc.',
                          filled: true,
                          fillColor: const Color(0xFFF7F8FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: _orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Block these dates',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Calendar holds',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: CircularProgressIndicator(color: _orange),
                          ),
                        )
                      else if (_stays.isEmpty)
                        Text(
                          'No upcoming holds on the calendar.',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else ...[
                        for (final stay in _stays)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: ListTile(
                              title: Text(
                                '${_dateFmt.format(stay.checkIn)} → ${_dateFmt.format(stay.checkOut)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                stay.isOffline
                                    ? [
                                        'Offline block',
                                        if ((stay.guestLabel ?? '').isNotEmpty)
                                          stay.guestLabel!,
                                        if ((stay.note ?? '').isNotEmpty)
                                          stay.note!,
                                      ].join(' · ')
                                    : 'Vero app booking',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: stay.isOffline
                                  ? IconButton(
                                      tooltip: 'Remove block',
                                      icon: Icon(
                                        Icons.event_busy_rounded,
                                        color: Colors.red.shade700,
                                      ),
                                      onPressed: () => _removeBlock(stay),
                                    )
                                  : Chip(
                                      label: const Text(
                                        'App',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      backgroundColor: Colors.blue.shade50,
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                    ),
                            ),
                          ),
                        if (offlineStays.isEmpty && _stays.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Only offline blocks can be removed here.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
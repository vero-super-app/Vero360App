import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_company_widgets.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_section_frame.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_skeletons.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_status_badge.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';

/// A booking seen by the providing company, with the actions staff can take.
class CarHireCompanyBookingPage extends ConsumerWidget {
  const CarHireCompanyBookingPage({super.key, required this.bookingId});

  final int bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingAsync = ref.watch(carHireBookingDetailProvider(bookingId));
    final access = ref.watch(companyAccessProvider).value;
    final canManage = access?.canManageBookings ?? false;

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: bookingAsync.value?.bookingNumberLabel ?? 'Booking',
      ),
      body: bookingAsync.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        skipError: true,
        loading: () => const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: CarHireCompanyBookingSkeleton(),
        ),
        error: (error, _) => CarHireErrorState(
          error: error,
          onRetry: () =>
              ref.invalidate(carHireBookingDetailProvider(bookingId)),
        ),
        data: (booking) => RefreshIndicator(
          color: CarHirePalette.accent,
          onRefresh: () async {
            ref.invalidate(bookingExtensionsProvider(bookingId));
            ref.invalidate(bookingIncidentsProvider(bookingId));
            try {
              await ref.read(carHireBookingDetailProvider(bookingId).future);
            } catch (_) {
              // The inline section state keeps the last good booking on screen.
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (bookingAsync.hasError)
                CarHireSectionStaleStrip(
                  message: 'Showing the saved booking. Live updates failed.',
                  padding: const EdgeInsets.only(bottom: 10),
                  onRefresh: () =>
                      ref.invalidate(carHireBookingDetailProvider(bookingId)),
                )
              else if (bookingAsync.isLoading)
                const CarHireSectionUpdatingStrip(
                  message: 'Refreshing booking…',
                  padding: EdgeInsets.only(bottom: 10),
                ),
              _Summary(booking: booking),
              const SizedBox(height: 12),
              if (canManage)
                _Actions(booking: booking)
              else
                const CarHireInfoBanner(
                  icon: Icons.visibility_outlined,
                  title: 'View only',
                  message:
                      'Ask the company owner for the manage bookings '
                      'permission to accept, hand over or close rentals.',
                ),
              _Extensions(booking: booking, canManage: canManage),
              _Incidents(booking: booking, canManage: canManage),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.booking});

  final CarHireBooking booking;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Car', booking.car?.title ?? 'Car #${booking.carId ?? '—'}'),
      if (booking.assignedPlate != null)
        (
          'Unit',
          [
            booking.assignedPlate!,
            if (booking.assignedColor != null) booking.assignedColor!,
          ].join(' · '),
        ),
      ('Dates', booking.dateRangeLabel),
      ('Renter', booking.renterName ?? 'Not shared'),
      if (booking.renterPhone != null) ('Phone', booking.renterPhone!),
      ('Total', booking.totalLabel),
      ('Payment', booking.paymentLabel),
      if (booking.renterNotes != null) ('Notes', booking.renterNotes!),
    ];

    return CarHireSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              CarHireStatusBadge.booking(booking.bookingStatus),
              CarHireStatusBadge.payment(booking.paymentStatus),
              if (booking.isRequest)
                const CarHirePill(
                  label: 'Request to book',
                  icon: Icons.schedule_rounded,
                  background: CarHirePalette.warningSoft,
                  foreground: CarHirePalette.warning,
                  fontSize: 10.5,
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(label, style: CarHireType.labelSmall),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: CarHireType.body.copyWith(
                        color: CarHirePalette.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (booking.isRequest &&
              booking.bookingStatus == BookingStatus.pending &&
              booking.holdExpiresAt != null)
            Text(
              'Respond before ${booking.holdExpiryLabel.replaceFirst('Hold expires ', '')}. '
              'The renter pays after you accept.',
              style: CarHireType.bodySmall.copyWith(
                color: CarHirePalette.warning,
              ),
            ),
        ],
      ),
    );
  }
}

/// Runs a company action and reports the outcome in a snack bar.
Future<bool> _runAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(CarHireApi api) action, {
  required int bookingId,
  required String success,
}) async {
  final ok = await ref
      .read(companyActionProvider.notifier)
      .run(action, bookingId: bookingId);
  if (!context.mounted) return ok;
  showCompanySnack(
    context,
    ok
        ? success
        : ref.read(companyActionProvider).error?.message ??
              'That did not work. Please try again.',
    error: !ok,
  );
  return ok;
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  required String confirm,
  bool required = false,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLength: 500,
        maxLines: 3,
        minLines: 1,
        decoration: carHireInputDecoration(label: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () {
            final text = controller.text.trim();
            if (required && text.isEmpty) return;
            Navigator.of(dialogContext).pop(text);
          },
          child: Text(confirm),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.booking});

  final CarHireBooking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(companyActionProvider).submitting;
    final id = booking.id;
    final status = booking.bookingStatus;
    final buttons = <Widget>[];

    void primary(String label, VoidCallback onPressed) {
      buttons.add(
        FilledButton(
          onPressed: busy ? null : onPressed,
          style: carHirePrimaryButton(),
          child: Text(label),
        ),
      );
    }

    void secondary(String label, VoidCallback onPressed, {Color? color}) {
      buttons.add(
        OutlinedButton(
          onPressed: busy ? null : onPressed,
          style: carHireGhostButton(foreground: color),
          child: Text(label),
        ),
      );
    }

    if (status == BookingStatus.pending) {
      primary(
        booking.isRequest ? 'Accept request' : 'Confirm booking',
        () => _runAction(
          context,
          ref,
          (api) => api.confirmBooking(id),
          bookingId: id,
          success: booking.isRequest
              ? 'Accepted. The renter has been asked to pay.'
              : 'Booking confirmed.',
        ),
      );
      secondary('Decline', () async {
        final reason = await _askText(
          context,
          title: 'Decline this booking?',
          label: 'Reason for the renter (optional)',
          confirm: 'Decline',
        );
        if (reason == null || !context.mounted) return;
        await _runAction(
          context,
          ref,
          (api) => api.rejectBooking(id, reason: reason),
          bookingId: id,
          success: 'Booking declined.',
        );
      }, color: CarHirePalette.error);
    } else if (status == BookingStatus.confirmed) {
      primary(
        'Record pickup inspection',
        () => CarHireRoutes.openInspection(
          context,
          bookingId: id,
          type: InspectionType.pickup,
          booking: booking,
          asCompany: true,
        ),
      );
      secondary(
        'Start rental',
        () => _runAction(
          context,
          ref,
          (api) => api.setRentalStage(id, start: true),
          bookingId: id,
          success: 'Rental started.',
        ),
      );
    } else if (status == BookingStatus.active ||
        status == BookingStatus.incidentReported) {
      primary(
        'Record return inspection',
        () => CarHireRoutes.openInspection(
          context,
          bookingId: id,
          type: InspectionType.returnInspection,
          booking: booking,
          asCompany: true,
        ),
      );
      secondary(
        'Complete rental',
        () => _runAction(
          context,
          ref,
          (api) => api.setRentalStage(id, start: false),
          bookingId: id,
          success: 'Rental completed.',
        ),
      );
    }

    final canSwap =
        status == BookingStatus.pending || status == BookingStatus.confirmed;
    if (canSwap) {
      secondary(
        booking.assignedPlate == null ? 'Assign unit' : 'Change unit',
        () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: CarHirePalette.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => _UnitSheet(booking: booking),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final button in buttons)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: button),
        ],
      ),
    );
  }
}

class _UnitSheet extends ConsumerWidget {
  const _UnitSheet({required this.booking});

  final CarHireBooking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(bookingUnitOptionsProvider(booking.id));
    final busy = ref.watch(companyActionProvider).submitting;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Choose a unit', style: CarHireType.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'Only units free for these dates can be picked. '
              'The renter is told about the change.',
              style: CarHireType.bodySmall,
            ),
            const SizedBox(height: 12),
            options.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: CarHireCompanyRowSkeleton(count: 3),
              ),
              error: (error, _) => CarHireInlineError(
                message: error is CarHireApiException
                    ? error.message
                    : 'Could not load the units.',
                onRetry: () =>
                    ref.invalidate(bookingUnitOptionsProvider(booking.id)),
              ),
              data: (units) => Column(
                children: [
                  for (final unit in units)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      enabled: !busy && unit.selectable && !unit.current,
                      leading: Icon(
                        unit.current
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: unit.current
                            ? CarHirePalette.accent
                            : CarHirePalette.muted,
                      ),
                      title: Text(unit.label),
                      subtitle: Text(_unitState(unit)),
                      onTap: () async {
                        final ok = await _runAction(
                          context,
                          ref,
                          (api) =>
                              api.assignBookingUnit(booking.id, unit.carId),
                          bookingId: booking.id,
                          success:
                              'Unit changed to ${unit.licensePlate ?? unit.label}.',
                        );
                        if (ok && context.mounted) Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _unitState(BookingUnitOption unit) {
    if (unit.current) return 'Assigned now';
    if (!unit.inService) return 'Out of service';
    return unit.freeForBooking ? 'Free for these dates' : 'Busy on these dates';
  }
}

class _Extensions extends ConsumerWidget {
  const _Extensions({required this.booking, required this.canManage});

  final CarHireBooking booking;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extensions = ref.watch(bookingExtensionsProvider(booking.id));
    final busy = ref.watch(companyActionProvider).submitting;
    final rows = extensions.value ?? const <BookingExtension>[];
    if (extensions.hasError && !extensions.hasValue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: Text('Extension requests', style: CarHireType.title),
          ),
          CarHireSectionErrorStrip(
            message: 'Extension requests could not load.',
            padding: EdgeInsets.zero,
            onRetry: () =>
                ref.invalidate(bookingExtensionsProvider(booking.id)),
          ),
        ],
      );
    }
    if (extensions.isLoading && !extensions.hasValue) {
      return const Padding(
        padding: EdgeInsets.only(top: 14, bottom: 4),
        child: CarHireCompanyRowSkeleton(count: 1),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CompanyGroupHeader(title: 'Extension requests', count: rows.length),
        if (extensions.hasError)
          CarHireSectionStaleStrip(
            message: 'Extensions may be out of date.',
            padding: const EdgeInsets.only(bottom: 8),
            onRefresh: () =>
                ref.invalidate(bookingExtensionsProvider(booking.id)),
          ),
        for (final extension in rows)
          CarHireSurface(
            margin: const EdgeInsets.only(bottom: 8),
            radius: CarHireShape.tileRadius,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Until ${extension.requestedEndLabel}',
                        style: CarHireType.subtitle,
                      ),
                    ),
                    CarHireStatusBadge.extension(extension.status),
                  ],
                ),
                if (extension.hasAdditionalAmount)
                  Text(
                    'Extra ${extension.additionalAmountLabel}',
                    style: CarHireType.bodySmall,
                  ),
                if (canManage && extension.status.isOpen) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final reason = await _askText(
                                    context,
                                    title: 'Decline extension?',
                                    label: 'Reason (optional)',
                                    confirm: 'Decline',
                                  );
                                  if (reason == null || !context.mounted) {
                                    return;
                                  }
                                  await _runAction(
                                    context,
                                    ref,
                                    (api) => api.decideExtension(
                                      booking.id,
                                      extension.id,
                                      approve: false,
                                      reason: reason,
                                    ),
                                    bookingId: booking.id,
                                    success: 'Extension declined.',
                                  );
                                },
                          style: carHireGhostButton(
                            foreground: CarHirePalette.error,
                          ),
                          child: const Text('Decline'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: busy
                              ? null
                              : () => _runAction(
                                  context,
                                  ref,
                                  (api) => api.decideExtension(
                                    booking.id,
                                    extension.id,
                                    approve: true,
                                  ),
                                  bookingId: booking.id,
                                  success: 'Extension approved.',
                                ),
                          style: carHirePrimaryButton(),
                          child: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _Incidents extends ConsumerWidget {
  const _Incidents({required this.booking, required this.canManage});

  final CarHireBooking booking;
  final bool canManage;

  static const _remedies = <(String, String)>[
    ('NONE', 'No remedy'),
    ('REPLACEMENT', 'Replacement car'),
    ('PARTIAL_REFUND', 'Partial refund'),
    ('REFUND', 'Refund'),
    ('EXTENSION', 'Extension'),
    ('ESCALATION', 'Escalate to Vero360'),
  ];

  bool _isOpen(IncidentReport incident) {
    final status = incident.status.toUpperCase();
    return status != 'RESOLVED' && status != 'CLOSED';
  }

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    IncidentReport incident,
  ) async {
    final controller = TextEditingController();
    var remedy = 'NONE';
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Resolve incident'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 3,
                minLines: 2,
                decoration: carHireInputDecoration(label: 'What was done'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: remedy,
                decoration: carHireInputDecoration(label: 'Remedy'),
                items: [
                  for (final (value, label) in _remedies)
                    DropdownMenuItem(value: value, child: Text(label)),
                ],
                onChanged: (value) => setState(() => remedy = value ?? 'NONE'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.of(dialogContext).pop((text, remedy));
              },
              child: const Text('Resolve'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !context.mounted) return;
    await _runAction(
      context,
      ref,
      (api) => api.resolveIncident(
        booking.id,
        incident.id,
        resolution: result.$1,
        remedy: result.$2,
      ),
      bookingId: booking.id,
      success: 'Incident resolved.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incidents = ref.watch(bookingIncidentsProvider(booking.id));
    final busy = ref.watch(companyActionProvider).submitting;
    final rows = incidents.value ?? const <IncidentReport>[];
    if (incidents.hasError && !incidents.hasValue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: Text('Incidents', style: CarHireType.title),
          ),
          CarHireSectionErrorStrip(
            message: 'Incidents could not load.',
            padding: EdgeInsets.zero,
            onRetry: () => ref.invalidate(bookingIncidentsProvider(booking.id)),
          ),
        ],
      );
    }
    if (incidents.isLoading && !incidents.hasValue) {
      return const Padding(
        padding: EdgeInsets.only(top: 14, bottom: 4),
        child: CarHireCompanyRowSkeleton(count: 1),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CompanyGroupHeader(title: 'Incidents', count: rows.length),
        if (incidents.hasError)
          CarHireSectionStaleStrip(
            message: 'Incidents may be out of date.',
            padding: const EdgeInsets.only(bottom: 8),
            onRefresh: () =>
                ref.invalidate(bookingIncidentsProvider(booking.id)),
          ),
        for (final incident in rows)
          CarHireSurface(
            margin: const EdgeInsets.only(bottom: 8),
            radius: CarHireShape.tileRadius,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        incident.typeLabel,
                        style: CarHireType.subtitle,
                      ),
                    ),
                    Text(incident.statusLabel, style: CarHireType.labelSmall),
                  ],
                ),
                const SizedBox(height: 3),
                Text(incident.description, style: CarHireType.bodySmall),
                Text(incident.occurredAtLabel, style: CarHireType.labelSmall),
                if (canManage && _isOpen(incident)) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _resolve(context, ref, incident),
                    style: carHireGhostButton(),
                    child: const Text('Resolve'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

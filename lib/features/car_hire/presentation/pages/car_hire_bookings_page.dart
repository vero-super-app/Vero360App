import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_status_badge.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

enum _BookingScope { all, upcoming, past }

extension on _BookingScope {
  String get label {
    switch (this) {
      case _BookingScope.all:
        return 'All';
      case _BookingScope.upcoming:
        return 'Upcoming';
      case _BookingScope.past:
        return 'Past';
    }
  }
}

class CarHireBookingsPage extends ConsumerStatefulWidget {
  const CarHireBookingsPage({super.key});

  @override
  ConsumerState<CarHireBookingsPage> createState() =>
      _CarHireBookingsPageState();
}

class _CarHireBookingsPageState extends ConsumerState<CarHireBookingsPage> {
  _BookingScope _scope = _BookingScope.all;

  Future<void> _refresh() async {
    ref.invalidate(myCarHireBookingsProvider);
    try {
      await ref.read(myCarHireBookingsProvider.future);
    } catch (_) {
      // The provider renders the error state.
    }
  }

  List<CarHireBooking> _visible(List<CarHireBooking> bookings) {
    switch (_scope) {
      case _BookingScope.all:
        return bookings;
      case _BookingScope.upcoming:
        return bookings
            .where((booking) => booking.bookingStatus.isOpen)
            .toList(growable: false);
      case _BookingScope.past:
        return bookings
            .where((booking) => !booking.bookingStatus.isOpen)
            .toList(growable: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(myCarHireBookingsProvider);

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: 'My bookings',
        actions: [
          CarHireIconButton(
            icon: Icons.verified_user_outlined,
            tooltip: 'Driver verification',
            onTap: () => CarHireRoutes.openVerification(context),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        color: CarHirePalette.accent,
        backgroundColor: CarHirePalette.surface,
        onRefresh: _refresh,
        child: bookings.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              CarHireLoadingState(message: 'Loading your bookings…'),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 60),
              CarHireErrorState(
                error: error,
                onRetry: _refresh,
              ),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 60),
                  CarHireEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No car hire bookings yet',
                    message: 'Your car hire bookings will appear here.',
                    actionLabel: 'Browse cars',
                    onAction: () => CarHireRoutes.openBrowse(context),
                  ),
                ],
              );
            }

            final visible = _visible(items);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _BookingScope.values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final scope = _BookingScope.values[index];
                      final selected = scope == _scope;
                      return _ScopeChip(
                        label: scope.label,
                        selected: selected,
                        onTap: () => setState(() => _scope = scope),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                if (visible.isEmpty)
                  CarHireSurface(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.luggage_outlined,
                          size: 28,
                          color: CarHirePalette.muted,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Nothing in ${_scope.label.toLowerCase()} trips',
                          style: CarHireType.subtitle,
                        ),
                      ],
                    ),
                  )
                else
                  for (final booking in visible)
                    _BookingListCard(
                      booking: booking,
                      onTap: () => CarHireRoutes.openBookingDetail(
                        context,
                        bookingId: booking.id,
                        initialBooking: booking,
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: CarHireShape.fast,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? CarHirePalette.primary : CarHirePalette.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? CarHirePalette.primary
                  : CarHirePalette.hairline,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : CarHirePalette.onSurfaceVariant,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingListCard extends StatelessWidget {
  const _BookingListCard({required this.booking, required this.onTap});

  final CarHireBooking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final car = booking.car;
    final image = car?.primaryImage;

    return CarHireSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 84,
                    height: 76,
                    child: image == null || image.isEmpty
                        ? Container(
                            color: CarHirePalette.surfaceLow,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.directions_car_filled_rounded,
                              color: CarHirePalette.outlineVariant,
                            ),
                          )
                        : ResilientCachedNetworkImage(
                            url: image,
                            fit: BoxFit.cover,
                            width: 84,
                            height: 76,
                            memCacheWidth: 260,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              booking.bookingNumberLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CarHireType.labelSmall,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: CarHireStatusBadge.booking(
                              booking.bookingStatus,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        car?.title ?? 'Vehicle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CarHireType.subtitle,
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.event_outlined,
                            size: 13,
                            color: CarHirePalette.muted,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              booking.dateRangeLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: CarHireType.labelSmall.copyWith(
                                fontSize: 10.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: CarHirePalette.hairline),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total', style: CarHireType.labelSmall),
                      const SizedBox(height: 1),
                      Text(
                        booking.totalLabel,
                        style: CarHireType.priceSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: CarHireStatusBadge.payment(
                      booking.paymentStatus,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: CarHirePalette.muted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

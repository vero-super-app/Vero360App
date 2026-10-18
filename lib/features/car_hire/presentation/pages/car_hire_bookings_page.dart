import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_status_badge.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

class CarHireBookingsPage extends ConsumerWidget {
  const CarHireBookingsPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(myCarHireBookingsProvider);
    try {
      await ref.read(myCarHireBookingsProvider.future);
    } catch (_) {
      // The provider renders the error state.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(myCarHireBookingsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: CarRentalColors.title,
        elevation: 0.4,
        scrolledUnderElevation: 0.4,
        title: const Text(
          'My car hire bookings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _refresh(ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: CarRentalColors.brandOrange,
        onRefresh: () => _refresh(ref),
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
                onRetry: () => _refresh(ref),
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
                    message:
                        'When you book a car, your booking and payment status '
                        'will appear here.',
                    actionLabel: 'Browse cars',
                    onAction: () => CarHireRoutes.openBrowse(context),
                  ),
                ],
              );
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final booking = items[index];
                return _BookingListCard(
                  booking: booking,
                  onTap: () => CarHireRoutes.openBookingDetail(
                    context,
                    bookingId: booking.id,
                    initialBooking: booking,
                  ),
                );
              },
            );
          },
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE7DF)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 72,
                        height: 64,
                        child: image == null || image.isEmpty
                            ? Container(
                                color: CarRentalColors.chip,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.directions_car_filled_rounded,
                                  color: CarRentalColors.grey,
                                ),
                              )
                            : ResilientCachedNetworkImage(
                                url: image,
                                fit: BoxFit.cover,
                                width: 72,
                                height: 64,
                                memCacheWidth: 220,
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
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
                                  style: const TextStyle(
                                    color: CarRentalColors.body,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
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
                          const SizedBox(height: 3),
                          Text(
                            car?.title ?? 'Vehicle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CarRentalColors.title,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            booking.dateRangeLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CarRentalColors.body,
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        booking.totalLabel,
                        style: const TextStyle(
                          color: CarRentalColors.title,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: CarHireStatusBadge.payment(
                        booking.paymentStatus,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

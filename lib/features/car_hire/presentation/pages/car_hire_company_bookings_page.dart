import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_company_widgets.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';

/// The company's booking inbox: requests that need an answer, upcoming
/// handovers and everything currently on rent.
class CarHireCompanyBookingsPage extends ConsumerWidget {
  const CarHireCompanyBookingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(companyAccessProvider);

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(title: 'Bookings'),
      body: access.when(
        loading: () => const CarHireLoadingState(message: 'Loading bookings…'),
        error: (error, _) => CarHireErrorState(
          error: error,
          onRetry: () => ref.invalidate(companyAccessProvider),
        ),
        data: (access) {
          if (!access.canViewBookings) {
            return const CarHireEmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'No booking access',
              message: 'Your membership does not include bookings. '
                  'Ask the company owner for the bookings permission.',
            );
          }
          return const _BookingsView();
        },
      ),
    );
  }
}

class _BookingsView extends ConsumerStatefulWidget {
  const _BookingsView();

  @override
  ConsumerState<_BookingsView> createState() => _BookingsViewState();
}

class _BookingsViewState extends ConsumerState<_BookingsView> {
  static const _filters = <(String, String)>[
    ('PENDING', 'Needs action'),
    ('CONFIRMED', 'Upcoming'),
    ('ACTIVE', 'On rent'),
    ('', 'All'),
  ];

  String _status = 'PENDING';

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(companyBookingsProvider(_status));

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            children: [
              for (final (status, label) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                    selectedColor: CarHirePalette.accentSoft,
                    labelStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: CarHirePalette.accent,
            onRefresh: () =>
                ref.refresh(companyBookingsProvider(_status).future),
            child: bookings.when(
              loading: () => const CarHireLoadingState(
                message: 'Loading bookings…',
              ),
              error: (error, _) => ListView(
                children: [
                  CarHireErrorState(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(companyBookingsProvider(_status)),
                  ),
                ],
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return ListView(
                    children: const [
                      CarHireEmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'Nothing here',
                        message: 'No bookings match this filter.',
                      ),
                    ],
                  );
                }
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        rows.length == 1
                            ? '1 booking'
                            : '${rows.length} bookings',
                        style: CarHireType.labelSmall,
                      ),
                    ),
                    for (final booking in rows)
                      CompanyBookingTile(
                        booking: booking,
                        onTap: () => CarHireRoutes.openCompanyBooking(
                          context,
                          bookingId: booking.id,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

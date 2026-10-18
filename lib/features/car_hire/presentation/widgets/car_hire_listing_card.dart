import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Public vehicle card. The public model never carries a registration plate,
/// so nothing private can be rendered here.
class CarHireListingCard extends StatelessWidget {
  const CarHireListingCard({
    super.key,
    required this.car,
    required this.onTap,
    this.margin = const EdgeInsets.only(bottom: 14),
  });

  final CarListing car;
  final VoidCallback onTap;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final available = car.isAvailable && car.availableForDates != false;

    return Semantics(
      button: true,
      label: '${car.title}, ${car.pricePerDayLabel}',
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          color: CarRentalColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEDE7DF)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _image(available),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  car.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: CarRentalColors.title,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                                ),
                                if (car.subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    car.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: CarRentalColors.body,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                car.pricePerDayLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: CarRentalColors.brandOrange,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Text(
                                'per day',
                                style: TextStyle(
                                  color: CarRentalColors.grey,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _SpecChip(
                            icon: Icons.event_seat_rounded,
                            label: car.seats == null
                                ? 'Seats n/a'
                                : '${car.seats} seats',
                          ),
                          _SpecChip(
                            icon: Icons.settings_rounded,
                            label: car.transmissionLabel,
                          ),
                          _SpecChip(
                            icon: Icons.local_gas_station_rounded,
                            label: car.fuelLabel,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            size: 15,
                            color: CarRentalColors.body,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              car.pickupAreaLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: CarRentalColors.body,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (!available)
                            const Text(
                              'Unavailable',
                              style: TextStyle(
                                color: CarRentalColors.error,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _image(bool available) {
    final url = car.primaryImage;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
      child: SizedBox(
        height: 168,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url == null || url.isEmpty)
              Container(
                color: CarRentalColors.chip,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  size: 42,
                  color: CarRentalColors.grey,
                ),
              )
            else
              ResilientCachedNetworkImage(
                url: url,
                fit: BoxFit.cover,
                height: 168,
                memCacheWidth: 900,
              ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      available
                          ? Icons.check_circle_rounded
                          : Icons.do_not_disturb_on_rounded,
                      size: 13,
                      color: available
                          ? CarRentalColors.success
                          : CarRentalColors.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      available ? 'Available' : 'Unavailable',
                      style: TextStyle(
                        color: available
                            ? CarRentalColors.success
                            : CarRentalColors.error,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecChip extends StatelessWidget {
  const _SpecChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: CarRentalColors.chip,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: CarRentalColors.greyDark),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: CarRentalColors.greyDark,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

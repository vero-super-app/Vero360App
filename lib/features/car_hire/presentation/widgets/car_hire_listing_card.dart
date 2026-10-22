import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Public vehicle card. The public model never carries a registration plate,
/// so nothing private can be rendered here.
class CarHireListingCard extends StatelessWidget {
  const CarHireListingCard({
    super.key,
    required this.car,
    required this.onTap,
    this.rentalDays = 0,
    this.margin = const EdgeInsets.only(bottom: 20),
  });

  final CarListing car;
  final VoidCallback onTap;

  /// Length of the selected rental, used only for a clearly-labelled estimate.
  final int rentalDays;
  final EdgeInsets margin;

  bool get _available => car.isAvailable && car.availableForDates != false;

  String get _specLine {
    String humanize(String? value) {
      final raw = (value ?? '').trim();
      if (raw.isEmpty) return '';
      final normalized = raw.replaceAll('_', ' ').toLowerCase();
      return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
    }

    return <String>[
      if (car.seats != null) '${car.seats} seats',
      humanize(car.transmission),
      humanize(car.fuelType),
    ].where((part) => part.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final estimate = rentalDays > 0 ? car.dailyRate * rentalDays : 0.0;
    final spec = _specLine;

    return Semantics(
      button: true,
      label:
          '${car.title}, '
          '${car.provider == null ? '' : '${car.providerLabel}, '}'
          '${car.pricePerDayLabel}'
          '${_available ? '' : ', unavailable'}'
          '${_available && car.unitsLeftLabel != null ? ', ${car.unitsLeftLabel}' : ''}',
      child: Padding(
        padding: margin,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(CarHireShape.cardRadius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _image(),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        car.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CarHireType.subtitle.copyWith(fontSize: 15.5),
                      ),
                    ),
                    if (car.rating > 0) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.star_rounded,
                        size: 15,
                        color: CarHirePalette.onSurface,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        car.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: CarHirePalette.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (car.provider != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    car.provider!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CarHireType.bodySmall.copyWith(
                      color: CarHirePalette.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  [car.pickupAreaLabel, if (spec.isNotEmpty) spec].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CarHireType.bodySmall,
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: CarHireFormatters.formatCurrency(car.dailyRate),
                        style: const TextStyle(
                          color: CarHirePalette.onSurface,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const TextSpan(text: ' / day'),
                      if (estimate > 0)
                        TextSpan(
                          text:
                              '  ·  '
                              '${CarHireFormatters.formatCurrency(estimate)} total',
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CarHirePalette.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _image() {
    final url = car.primaryImage;

    return ClipRRect(
      borderRadius: BorderRadius.circular(CarHireShape.cardRadius),
      child: SizedBox(
        height: 190,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url == null || url.isEmpty)
              Container(
                color: CarHirePalette.surfaceLow,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  size: 44,
                  color: CarHirePalette.outlineVariant,
                ),
              )
            else
              ResilientCachedNetworkImage(
                url: url,
                fit: BoxFit.cover,
                height: 190,
                memCacheWidth: 1000,
              ),
            if (!_available) ...[
              Container(color: Colors.white.withValues(alpha: 0.45)),
              Positioned(
                left: 12,
                top: 12,
                child: CarHirePill(
                  label: 'Unavailable',
                  background: Colors.white.withValues(alpha: 0.95),
                  foreground: CarHirePalette.error,
                  fontSize: 11,
                ),
              ),
            ] else if (car.unitsLeftLabel != null)
              Positioned(
                left: 12,
                top: 12,
                child: CarHirePill(
                  label: car.unitsLeftLabel!,
                  background: Colors.white.withValues(alpha: 0.95),
                  foreground: CarHirePalette.onSurface,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

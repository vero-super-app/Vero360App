import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Relative price position used to pick an editorial badge on the card.
enum CarPriceBand { value, standard, premium }

enum _CardBadge { instant, electric, executive, topValue, unavailable }

/// Public vehicle card. The public model never carries a registration plate,
/// so nothing private can be rendered here.
class CarHireListingCard extends StatelessWidget {
  const CarHireListingCard({
    super.key,
    required this.car,
    required this.onTap,
    this.rentalDays = 0,
    this.priceBand = CarPriceBand.standard,
    this.margin = const EdgeInsets.only(bottom: 16),
  });

  final CarListing car;
  final VoidCallback onTap;

  /// Length of the selected rental, used only for a clearly-labelled estimate.
  final int rentalDays;
  final CarPriceBand priceBand;
  final EdgeInsets margin;

  bool get _available => car.isAvailable && car.availableForDates != false;

  bool get _isElectric {
    final fuel = (car.fuelType ?? '').toUpperCase();
    return fuel.contains('ELECTRIC') || fuel.contains('EV');
  }

  _CardBadge get _badge {
    if (!_available) return _CardBadge.unavailable;
    if (_isElectric) return _CardBadge.electric;
    switch (priceBand) {
      case CarPriceBand.premium:
        return _CardBadge.executive;
      case CarPriceBand.value:
        return _CardBadge.topValue;
      case CarPriceBand.standard:
        return _CardBadge.instant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${car.title}, ${car.pricePerDayLabel}',
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          color: CarHirePalette.surface,
          borderRadius: BorderRadius.circular(CarHireShape.cardRadius),
          border: Border.all(color: CarHirePalette.hairline),
          boxShadow: CarHireShape.cardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(CarHireShape.cardRadius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _image(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _titleRow(),
                      const SizedBox(height: 3),
                      _locationLine(),
                      const SizedBox(height: 14),
                      _specGrid(),
                      const SizedBox(height: 14),
                      _priceRow(),
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

  Widget _titleRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            car.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: CarHireType.title.copyWith(fontSize: 18),
          ),
        ),
        if (car.rating > 0 || car.reviews > 0) ...[
          const SizedBox(width: 8),
          CarHireRatingPill(rating: car.rating, reviews: car.reviews),
        ],
      ],
    );
  }

  Widget _locationLine() {
    final parts = <String>[
      car.pickupAreaLabel,
      if (car.subtitle.isNotEmpty) car.subtitle,
    ];
    return Row(
      children: [
        const Icon(
          Icons.place_outlined,
          size: 13,
          color: CarHirePalette.muted,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            parts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CarHireType.bodySmall.copyWith(fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  Widget _specGrid() {
    final fuel = _humanize(car.fuelType, fallback: 'Fuel n/a');
    final transmission = _humanize(car.transmission, fallback: 'Gearbox n/a');
    final body = _humanize(car.bodyType, fallback: 'Body n/a');

    return Row(
      children: [
        Expanded(
          child: _SpecTile(
            icon: Icons.airline_seat_recline_normal_rounded,
            label: car.seats == null ? 'Seats n/a' : '${car.seats} seats',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SpecTile(
            icon: _isElectric
                ? Icons.electric_car_rounded
                : Icons.local_gas_station_rounded,
            label: fuel,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SpecTile(
            icon: Icons.settings_input_component_rounded,
            label: transmission,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SpecTile(
            icon: Icons.directions_car_rounded,
            label: body,
          ),
        ),
      ],
    );
  }

  Widget _priceRow() {
    final estimate = rentalDays > 0 ? car.dailyRate * rentalDays : 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      CarHireFormatters.formatCurrency(car.dailyRate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CarHireType.price,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '/ day',
                    style: TextStyle(
                      color: CarHirePalette.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                estimate > 0
                    ? 'Est. ${CarHireFormatters.formatCurrency(estimate)} for $rentalDays ${rentalDays == 1 ? 'day' : 'days'}'
                    : 'Final quote at checkout',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CarHireType.labelSmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 44,
          child: FilledButton(
            onPressed: _available ? onTap : null,
            style: FilledButton.styleFrom(
              backgroundColor: CarHirePalette.accent,
              foregroundColor: CarHirePalette.onAccent,
              disabledBackgroundColor: CarHirePalette.surfaceContainer,
              disabledForegroundColor: CarHirePalette.muted,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
            child: Text(_available ? 'Rent now' : 'Unavailable'),
          ),
        ),
      ],
    );
  }

  Widget _image() {
    final url = car.primaryImage;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(CarHireShape.cardRadius),
      ),
      child: SizedBox(
        height: 176,
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
                height: 176,
                memCacheWidth: 1000,
              ),
            // A soft bottom scrim keeps overlaid controls legible on photos.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 64,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0),
                        Colors.black.withValues(alpha: 0.16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: _badgePill(),
            ),
            if (car.rating > 0 || car.reviews > 0)
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: CarHirePalette.accent,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        car.rating.toStringAsFixed(2),
                        style: const TextStyle(
                          color: CarHirePalette.onSurface,
                          fontSize: 11,
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

  Widget _badgePill() {
    late final String label;
    late final IconData icon;
    late final Color background;
    late final Color foreground;

    switch (_badge) {
      case _CardBadge.instant:
        label = 'Instant book';
        icon = Icons.bolt_rounded;
        background = CarHirePalette.primary;
        foreground = Colors.white;
        break;
      case _CardBadge.electric:
        label = 'EV · Instant book';
        icon = Icons.bolt_rounded;
        background = CarHirePalette.primary;
        foreground = const Color(0xFFFFDCC7);
        break;
      case _CardBadge.executive:
        label = 'Executive choice';
        icon = Icons.workspace_premium_rounded;
        background = CarHirePalette.primaryContainer;
        foreground = const Color(0xFFD4E3FF);
        break;
      case _CardBadge.topValue:
        label = 'Top value';
        icon = Icons.trending_up_rounded;
        background = CarHirePalette.accentSoft;
        foreground = CarHirePalette.onAccentSoft;
        break;
      case _CardBadge.unavailable:
        label = 'Unavailable';
        icon = Icons.do_not_disturb_on_rounded;
        background = Colors.white.withValues(alpha: 0.94);
        foreground = CarHirePalette.error;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  String _humanize(String? value, {required String fallback}) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return fallback;
    final normalized = raw.replaceAll('_', ' ').toLowerCase();
    return normalized
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class _SpecTile extends StatelessWidget {
  const _SpecTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: CarHirePalette.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: CarHirePalette.onSurfaceVariant),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: CarHirePalette.onSurface,
              fontSize: 10.5,
              height: 1.15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

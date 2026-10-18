import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/utils/formatters.dart';

/// Trip search form used inline on the browse page and inside the modal sheet.
class CarHireSearchForm extends StatelessWidget {
  const CarHireSearchForm({
    super.key,
    required this.pickupController,
    required this.startAt,
    required this.endAt,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onSearch,
    this.searching = false,
    this.showHeader = true,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 14),
  });

  final TextEditingController pickupController;
  final DateTime startAt;
  final DateTime endAt;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onSearch;
  final bool searching;
  final bool showHeader;
  final EdgeInsets padding;

  bool get _rangeInvalid => !endAt.isAfter(startAt);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: CarHireSurface(
        padding: const EdgeInsets.all(16),
        radius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader) ...[
              const Text('Plan your drive', style: CarHireType.overline),
              const SizedBox(height: 6),
              const Text('Where and when?', style: CarHireType.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Pick-up area is optional. Dates are checked against live '
                'availability.',
                style: CarHireType.bodySmall,
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: pickupController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSearch(),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: CarHirePalette.onSurface,
              ),
              decoration: carHireInputDecoration(
                label: 'Pick-up area',
                hint: 'City, neighbourhood or airport',
                prefixIcon: const Icon(
                  Icons.place_outlined,
                  size: 20,
                  color: CarHirePalette.accent,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateTimeField(
                    label: 'Pick-up',
                    date: startAt,
                    icon: Icons.flight_takeoff_rounded,
                    onTap: onPickStart,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateTimeField(
                    label: 'Return',
                    date: endAt,
                    icon: Icons.flight_land_rounded,
                    onTap: onPickEnd,
                  ),
                ),
              ],
            ),
            if (_rangeInvalid) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: CarHirePalette.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'The return date and time must be after pick-up.',
                      style: CarHireType.bodySmall.copyWith(
                        color: CarHirePalette.error,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: searching || _rangeInvalid ? null : onSearch,
              icon: searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search_rounded, size: 19),
              label: Text(searching ? 'Searching…' : 'Search cars'),
              style: carHirePrimaryButton(),
            ),
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 13,
                  color: CarHirePalette.muted,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Availability is confirmed by Vero360 for your full period.',
                    textAlign: TextAlign.center,
                    style: CarHireType.labelSmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.date,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label ${CarHireFormatters.formatDateTime(date)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: CarHirePalette.surfaceLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: CarHirePalette.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 13, color: CarHirePalette.accent),
                    const SizedBox(width: 5),
                    Text(
                      label.toUpperCase(),
                      style: CarHireType.overline.copyWith(fontSize: 9.5),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  CarHireFormatters.formatDate(date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CarHirePalette.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  CarHireFormatters.formatTime(date),
                  style: CarHireType.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

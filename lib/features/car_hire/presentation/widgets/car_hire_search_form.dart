import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';
import 'package:vero360_app/utils/formatters.dart';

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
  });

  final TextEditingController pickupController;
  final DateTime startAt;
  final DateTime endAt;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onSearch;
  final bool searching;

  bool get _rangeInvalid => !endAt.isAfter(startAt);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CarRentalColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDE7DF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: CarRentalColors.brandOrangePale,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: CarRentalColors.brandOrange,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Find a car for your trip',
                  style: TextStyle(
                    color: CarRentalColors.title,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: pickupController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: InputDecoration(
              hintText: 'Pick-up area (optional)',
              prefixIcon: const Icon(Icons.place_outlined, size: 20),
              filled: true,
              fillColor: CarRentalColors.greyLight,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE4DED6)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE4DED6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: CarRentalColors.brandOrange,
                  width: 1.4,
                ),
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
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: CarRentalColors.error,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'The return date and time must be after pick-up.',
                    style: TextStyle(
                      color: CarRentalColors.error,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
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
              style: FilledButton.styleFrom(
                backgroundColor: CarRentalColors.brandOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    CarRentalColors.brandOrange.withValues(alpha: 0.45),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Availability is checked by Vero360 for the complete selected '
            'period.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CarRentalColors.grey,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
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
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: CarRentalColors.greyLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4DED6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 13, color: CarRentalColors.brandOrange),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        color: CarRentalColors.body,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  CarHireFormatters.formatDate(date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CarRentalColors.title,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  CarHireFormatters.formatTime(date),
                  style: const TextStyle(
                    color: CarRentalColors.body,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

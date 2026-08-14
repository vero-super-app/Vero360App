import 'package:flutter/material.dart';

const kAccommodationAmenityPresets = <String>[
  'Wi-Fi',
  'Parking',
  'Swimming pool',
  'Breakfast included',
  'Air conditioning',
  'TV',
  'Kitchen',
  'Hot water',
  '24/7 security',
  'Laundry',
  'Gym',
  'Bar',
  'Conference room',
  'Garden',
  'Pet friendly',
  'Airport pickup',
];

List<String> parseAccommodationAmenities(Object? raw) {
  if (raw == null) return const [];
  final out = <String>[];
  void take(Object? v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty) return;
    if (!out.contains(s)) out.add(s);
  }

  if (raw is List) {
    for (final e in raw) {
      take(e);
    }
  } else if (raw is String) {
    for (final part in raw.split(RegExp(r'[,|;]'))) {
      take(part);
    }
  }
  return out;
}

class AccommodationAmenityPicker extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const AccommodationAmenityPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final extras = selected
        .where((s) => !kAccommodationAmenityPresets.contains(s))
        .toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final label in [...kAccommodationAmenityPresets, ...extras])
          FilterChip(
            label: Text(label),
            selected: selected.contains(label),
            onSelected: (on) {
              final next = {...selected};
              if (on) {
                next.add(label);
              } else {
                next.remove(label);
              }
              onChanged(next);
            },
            selectedColor: const Color(0xFFFF8A00).withValues(alpha: 0.18),
            checkmarkColor: const Color(0xFFFF8A00),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: selected.contains(label)
                  ? const Color(0xFF16284C)
                  : Colors.grey.shade800,
            ),
          ),
      ],
    );
  }
}

class AccommodationAmenityChips extends StatelessWidget {
  final List<String> amenities;

  const AccommodationAmenityChips({super.key, required this.amenities});

  @override
  Widget build(BuildContext context) {
    if (amenities.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in amenities)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A00).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFFFF8A00).withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: Color(0xFFFF8A00),
                ),
                const SizedBox(width: 4),
                Text(
                  a,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Color(0xFF16284C),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

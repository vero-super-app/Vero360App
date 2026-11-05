import 'package:flutter/material.dart';

/// Eye + count over a listing photo. [views] is how many times people opened it.
class ListingViewsBadge extends StatelessWidget {
  const ListingViewsBadge({super.key, required this.views});

  final int views;

  static String labelFor(int views) {
    final n = views < 0 ? 0 : views;
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final k = n / 1000;
      final text = k >= 10 ? k.round().toString() : k.toStringAsFixed(1);
      return '${text}k';
    }
    final m = n / 1000000;
    final text = m >= 10 ? m.round().toString() : m.toStringAsFixed(1);
    return '${text}m';
  }

  @override
  Widget build(BuildContext context) {
    final n = views < 0 ? 0 : views;
    final label = labelFor(n);
    return Semantics(
      label: '$n ${n == 1 ? 'view' : 'views'}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.visibility_rounded,
              color: Colors.white,
              size: 13,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

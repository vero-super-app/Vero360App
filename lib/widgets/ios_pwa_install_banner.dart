import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

/// iOS Safari has no install prompt. Tell people to Add to Home Screen.
class IosPwaInstallBanner extends StatelessWidget {
  const IosPwaInstallBanner({super.key});

  static bool get visible =>
      kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD9A8)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.ios_share_rounded, color: Color(0xFFE86F00)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Using iPhone? Tap Share, then Add to Home Screen. Vero360 opens like an app — no App Store wait.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7A4A12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

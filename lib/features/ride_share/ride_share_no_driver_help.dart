import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vero360_app/Quickservices/help_center_live_chat.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_in_ride_ui.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';
import 'package:vero360_app/features/ride_share/ride_share_contact_catalog.dart';

/// Shared copy + actions when matching finds no nearby drivers.
abstract final class RideShareNoDriverHelp {
  static const _genericNames = {
    'pickup',
    'dropoff',
    'current location',
    'my location',
    'your location',
    'here',
  };

  static bool isNoDriverReason(String? reason) {
    final lower = (reason ?? '').toLowerCase();
    return lower.contains('no driver') || lower.contains('no ride');
  }

  /// Short place name for “I did not find a ride in …”.
  static String locationLabel({
    String? name,
    String? address,
  }) {
    final n = (name ?? '').trim();
    if (n.isNotEmpty && !_genericNames.contains(n.toLowerCase())) {
      return n;
    }
    final a = (address ?? '').trim();
    if (a.isEmpty) return 'my area';
    final first = a.split(',').first.trim();
    return first.isEmpty ? 'my area' : first;
  }

  static String guidingMessage(String location) =>
      'I did not find a ride in $location.';

  static Future<void> openHelpCenter(
    BuildContext context, {
    required String message,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => HelpCenterLiveChatPage(initialMessage: message),
      ),
    );
  }

  static Future<void> openWhatsApp(
    BuildContext context, {
    required String message,
  }) async {
    await RideShareContactCatalog.instance.ensureStarted();
    final phone = RideShareContactCatalog.instance.whatsAppDigits;
    final encoded = Uri.encodeComponent(message);
    final candidates = <Uri>[
      Uri.parse('whatsapp://send?phone=$phone&text=$encoded'),
      Uri.parse('https://wa.me/$phone?text=$encoded'),
      Uri.parse('https://api.whatsapp.com/send?phone=$phone&text=$encoded'),
    ];

    for (final uri in candidates) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (_) {}
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open WhatsApp. Try Help Center instead.'),
      ),
    );
  }
}

/// Recovery actions: Help Center (primary, auto-sends guiding message) + WhatsApp.
class NoDriverHelpPanel extends StatelessWidget {
  const NoDriverHelpPanel({
    super.key,
    required this.locationLabel,
    this.onTryAgain,
    this.showHandle = false,
  });

  final String locationLabel;
  final VoidCallback? onTryAgain;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final message = RideShareNoDriverHelp.guidingMessage(locationLabel);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHandle)
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: RideShareColors.primarySoft,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(
            Icons.headset_mic_rounded,
            size: 34,
            color: RideShareColors.primaryDeep,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'No drivers nearby',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: RideShareColors.titleText,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'We couldn\'t find a driver in $locationLabel. Chat Help Center and we\'ll help arrange a ride.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Guiding message',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey[600],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: RideShareColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => RideShareNoDriverHelp.openHelpCenter(
              context,
              message: message,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 18,
                    color: RideShareColors.primaryDeep,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: RideShareColors.titleText,
                        height: 1.35,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey[500]),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        RidePrimaryCta(
          label: 'Chat Help Center',
          icon: Icons.headset_mic_rounded,
          onPressed: () => RideShareNoDriverHelp.openHelpCenter(
            context,
            message: message,
          ),
        ),
        const SizedBox(height: 10),
        RideSecondaryCta(
          label: 'WhatsApp instead',
          icon: Icons.chat_rounded,
          onPressed: () => RideShareNoDriverHelp.openWhatsApp(
            context,
            message: message,
          ),
        ),
        if (onTryAgain != null) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: onTryAgain,
            child: const Text(
              'Try again',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: RideShareColors.primaryDeep,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

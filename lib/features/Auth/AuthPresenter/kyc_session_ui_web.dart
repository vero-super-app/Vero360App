import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens Didit in a new browser tab (Safari PWA cannot host camera WebViews).
Future<bool?> openKycSession(BuildContext context, String verificationUrl) async {
  final uri = Uri.tryParse(verificationUrl);
  if (uri == null) return false;
  final opened = await launchUrl(uri, webOnlyWindowName: '_blank');
  if (!opened || !context.mounted) return false;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Finish identity check'),
        content: const Text(
          'Complete the ID and face check in the new tab. When Didit says you are done, come back here and tap I’m done.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I’m done'),
          ),
        ],
      );
    },
  );
}

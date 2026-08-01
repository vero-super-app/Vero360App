import 'package:flutter/material.dart';
import 'package:vero360_app/utils/chat_offplatform_detector.dart';

/// Inline chat notice shown under messages that share phone / bank details.
class ChatOffPlatformWarning extends StatelessWidget {
  const ChatOffPlatformWarning({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFE0A3)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: Color(0xFFC47F00),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                ChatOffPlatformDetector.warningText,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B4E00),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

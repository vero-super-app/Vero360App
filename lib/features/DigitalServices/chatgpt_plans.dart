import 'package:flutter/material.dart';
import 'package:vero360_app/features/DigitalServices/digital_product.dart';

/// ChatGPT plans shown on the Netflix-style chooser.
class ChatGptPlanSpec {
  final String key;
  final String title;
  final String badge;
  final List<String> featureLines;
  final bool recommended;

  const ChatGptPlanSpec({
    required this.key,
    required this.title,
    required this.badge,
    required this.featureLines,
    this.recommended = false,
  });
}

const List<ChatGptPlanSpec> kChatGptPlanSpecs = [
  ChatGptPlanSpec(
    key: 'chatgpt_basic',
    title: 'Basic ChatGPT Plus',
    badge: 'For students',
    recommended: true,
    featureLines: [
      'Shared account for up to 15 students',
      'Best for assignments and school work',
      'One shared login, so chats are not private',
    ],
  ),
  ChatGptPlanSpec(
    key: 'chatgpt_plus',
    title: 'ChatGPT Plus',
    badge: 'Private',
    featureLines: [
      'Your own account. Not shared with anyone',
      'Best for work and personal use',
      'Your chats stay private',
    ],
  ),
];

bool isChatGptHubKey(String key) => key.trim().toLowerCase() == 'chatgpt';

bool isChatGptPlanKey(String key) {
  final k = key.trim().toLowerCase();
  return k == 'chatgpt_basic' || k == 'chatgpt_plus';
}

ChatGptPlanSpec? chatGptPlanSpecForKey(String key) {
  final k = key.trim().toLowerCase();
  for (final s in kChatGptPlanSpecs) {
    if (s.key == k) return s;
  }
  return null;
}

/// Catalog shells. Prices are the customer prices; admin can still override.
const List<DigitalProduct> kChatGptPlanProducts = [
  DigitalProduct(
    key: 'chatgpt_basic',
    name: 'Basic ChatGPT Plus',
    subtitle: 'Shared · up to 15 students',
    category: 'streaming',
    accent: Color(0xFF10A37F),
    brandTag: 'Students',
    logoAsset: 'assets/brands/chatgpt.png',
    icon: Icons.chat_bubble_outline_rounded,
    fixedMwkPrice: 10000,
  ),
  DigitalProduct(
    key: 'chatgpt_plus',
    name: 'ChatGPT Plus',
    subtitle: 'Private · one account',
    category: 'streaming',
    accent: Color(0xFF10A37F),
    brandTag: 'Private',
    logoAsset: 'assets/brands/chatgpt.png',
    icon: Icons.chat_bubble_outline_rounded,
    fixedMwkPrice: 65000,
  ),
];

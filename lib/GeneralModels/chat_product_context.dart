import 'package:vero360_app/GernalServices/backend_chat_service.dart';

/// Product context passed when opening a merchant chat from marketplace.
class ChatProductContext {
  final String productId;
  final String name;
  final String? image;
  final double? price;
  final String? description;
  final String? merchantId;

  const ChatProductContext({
    required this.productId,
    required this.name,
    this.image,
    this.price,
    this.description,
    this.merchantId,
  });

  factory ChatProductContext.fromTagMap(Map<String, dynamic> tag) {
    final metadata = tag['metadata'];
    double? price;
    String? merchantId;
    if (metadata is Map) {
      if (metadata['price'] != null) {
        final raw = metadata['price'];
        price = raw is num ? raw.toDouble() : double.tryParse('$raw');
      }
      final mid = metadata['merchantId']?.toString().trim();
      if (mid != null && mid.isNotEmpty) {
        merchantId = mid;
      } else {
        final sp = metadata['serviceProviderId']?.toString().trim();
        if (sp != null && sp.isNotEmpty) merchantId = sp;
      }
    }

    return ChatProductContext(
      productId: '${tag['tagId'] ?? ''}',
      name: '${tag['tagName'] ?? 'Product'}',
      image: tag['tagImage']?.toString(),
      description: tag['tagDescription']?.toString(),
      price: price,
      merchantId: merchantId,
    );
  }

  /// Most recently tagged product in a message thread (scan newest first).
  static ChatProductContext? latestFromMessages(
    List<BackendChatMessage> messages,
  ) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final tags = messages[i].tags ?? const [];
      for (var j = tags.length - 1; j >= 0; j--) {
        final tag = tags[j];
        if (tag['tagType'] == 'product') {
          return ChatProductContext.fromTagMap(
            Map<String, dynamic>.from(tag),
          );
        }
      }
    }
    return null;
  }

  /// Tag payload for [BackendChatService.sendMessage].
  Map<String, dynamic> toMessageTag() {
    return {
      'tagType': 'product',
      'tagId': productId,
      'tagName': name,
      if (description != null && description!.trim().isNotEmpty)
        'tagDescription': description!.trim(),
      if (image != null && image!.trim().isNotEmpty) 'tagImage': image!.trim(),
      if (price != null || merchantId != null)
        'metadata': {
          if (price != null) 'price': price,
          if (merchantId != null && merchantId!.trim().isNotEmpty)
            'merchantId': merchantId!.trim(),
        },
    };
  }
}

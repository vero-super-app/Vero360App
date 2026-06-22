import 'package:vero360_app/GernalServices/backend_chat_service.dart';

/// Product context passed when opening a merchant chat from marketplace.
class ChatProductContext {
  final String productId;
  final String name;
  final String? image;
  final double? price;
  final String? description;

  const ChatProductContext({
    required this.productId,
    required this.name,
    this.image,
    this.price,
    this.description,
  });

  factory ChatProductContext.fromTagMap(Map<String, dynamic> tag) {
    final metadata = tag['metadata'];
    double? price;
    if (metadata is Map && metadata['price'] != null) {
      final raw = metadata['price'];
      price = raw is num ? raw.toDouble() : double.tryParse('$raw');
    }

    return ChatProductContext(
      productId: '${tag['tagId'] ?? ''}',
      name: '${tag['tagName'] ?? 'Product'}',
      image: tag['tagImage']?.toString(),
      description: tag['tagDescription']?.toString(),
      price: price,
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
      if (price != null) 'metadata': {'price': price},
    };
  }
}

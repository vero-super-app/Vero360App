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

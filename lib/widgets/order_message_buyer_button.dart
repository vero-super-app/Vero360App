import 'dart:async';

import 'package:flutter/material.dart';

import 'package:vero360_app/GeneralModels/chat_product_context.dart';
import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/Home/MessagePageBackendApi.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// Opens a direct chat with the buyer who placed [order].
class OrderBuyerChat {
  OrderBuyerChat._();

  /// First merchant→buyer chat note: we received the order; please confirm details.
  static String receivedOrderMessage({
    required String orderNumber,
    String customerName = '',
    String items = '',
    String phone = '',
    String deliveryAddress = '',
    String restaurantName = '',
    String total = '',
    bool food = false,
  }) {
    final name = customerName.trim();
    final hello = name.isEmpty ? 'Hi,' : 'Hi $name,';
    final ref = orderNumber.trim();
    final received = ref.isEmpty
        ? 'We have received your order.'
        : 'We have received your order $ref.';
    final lines = <String>[
      hello,
      '',
      received,
    ];
    if (items.trim().isNotEmpty) {
      lines.add('');
      lines.add('Items: ${items.trim()}');
    }
    if (total.trim().isNotEmpty) {
      lines.add('Total: ${total.trim()}');
    }
    if (restaurantName.trim().isNotEmpty) {
      lines.add('${food ? 'Restaurant' : 'Shop'}: ${restaurantName.trim()}');
    }
    lines.add('');
    lines.add('Please confirm your details:');
    lines.add('Name: ${name.isEmpty ? '—' : name}');
    if (phone.trim().isNotEmpty) {
      lines.add('Phone: ${phone.trim()}');
    }
    if (deliveryAddress.trim().isNotEmpty) {
      lines.add('Delivery address: ${deliveryAddress.trim()}');
    }
    lines.add('');
    lines.add(
      food
          ? 'Reply YES if this is correct, or send the right name, phone, or address so we can prepare and send your food.'
          : 'Reply YES if this is correct, or send the right name, phone, or address so we can send your order.',
    );
    return lines.join('\n');
  }

  static Future<void> open(BuildContext context, OrderItem order) {
    final buyerUid = (order.customerUid ?? '').trim();
    final sellerUid = (order.merchantUid ?? '').trim();
    final peerName = (order.customerName ?? '').trim().isEmpty
        ? 'Buyer'
        : order.customerName!.trim();
    final delivery = [
      if ((order.addressCity ?? '').trim().isNotEmpty)
        order.addressCity!.trim(),
      if ((order.addressDescription ?? '').trim().isNotEmpty)
        order.addressDescription!.trim(),
    ].join(' • ');
    final qty = order.quantity > 1
        ? '${order.quantity}× ${order.itemName}'
        : order.itemName;
    return openPeer(
      context,
      buyerUid: buyerUid,
      sellerUid: sellerUid,
      peerName: peerName,
      productId: order.id,
      productName: order.itemName,
      image: order.itemImage,
      price: order.price.toDouble(),
      description: 'Order ${order.orderNumber}',
      autoSendMessage: receivedOrderMessage(
        orderNumber: order.orderNumber,
        customerName: peerName == 'Buyer' ? '' : peerName,
        items: qty,
        phone: (order.customerPhone ?? '').trim(),
        deliveryAddress: delivery,
        restaurantName: (order.merchantName ?? '').trim(),
        total: 'MWK ${order.total}',
      ),
      autoSendClientMessageId: 'order-received-${order.id}',
    );
  }

  static Future<void> openPeer(
    BuildContext context, {
    required String buyerUid,
    String sellerUid = '',
    String peerName = 'Buyer',
    String productId = '',
    String productName = '',
    String? image,
    double price = 0,
    String description = '',
    String? autoSendMessage,
    String? autoSendClientMessageId,
  }) async {
    final uid = buyerUid.trim();
    final name = peerName.trim().isEmpty ? 'Buyer' : peerName.trim();
    if (uid.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Buyer contact is not available for messaging',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF8A00)),
      ),
    );

    try {
      unawaited(BackendChatService.warmForMarketplaceChat().catchError((_) {}));
      unawaited(BackendMessagingSocket.connect().catchError((_) {}));

      final peerUserId =
          await BackendChatService.getUserIdByFirebaseUidValidated(uid);
      if (peerUserId == null || peerUserId <= 0) {
        throw Exception('Could not find the buyer’s chat account.');
      }

      String chatId = '';
      final cached =
          BackendChatService.findCachedDirectChatWithPeer(peerUserId);
      if (cached != null) {
        chatId = cached.id;
      } else {
        final chat = await BackendChatService.ensureChat(
          peerUserId: peerUserId,
          peerName: name,
        );
        chatId = chat.id;
      }

      final img = (image ?? '').trim();
      final seller = sellerUid.trim();
      final productContext = ChatProductContext(
        productId: productId.trim(),
        name: productName.trim().isEmpty ? 'Order' : productName.trim(),
        image: img.isEmpty ? null : img,
        price: price,
        description: description.trim().isEmpty ? null : description.trim(),
        merchantId: seller.isEmpty ? null : seller,
      );

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MessagePageBackendApi(
            peerId: chatId,
            peerName: name,
            productContext: productContext,
            peerMerchantId: seller.isEmpty ? null : seller,
            peerUserId: peerUserId,
            autoSendMessage: autoSendMessage,
            autoSendClientMessageId: autoSendClientMessageId,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final raw = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      ToastHelper.showCustomToast(
        context,
        'Could not open chat',
        isSuccess: false,
        errorMessage: raw,
      );
    }
  }
}

/// Round orange chat button — messages the order’s buyer.
class OrderMessageBuyerButton extends StatelessWidget {
  final OrderItem order;
  final Color brand;

  const OrderMessageBuyerButton({
    super.key,
    required this.order,
    this.brand = const Color(0xFFFF8A00),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: brand,
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        onTap: () => OrderBuyerChat.open(context, order),
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.chat_bubble_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }
}

/// Product thumbnail with a centered round chat button below (spaced from image).
class OrderThumbWithBuyerChat extends StatelessWidget {
  final OrderItem order;
  final double size;
  final Color brand;
  final Widget? placeholder;

  const OrderThumbWithBuyerChat({
    super.key,
    required this.order,
    this.size = 72,
    this.brand = const Color(0xFFFF8A00),
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = order.itemImage.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: size,
            height: size,
            child: imageUrl.isEmpty
                ? (placeholder ??
                    Container(
                      color: const Color(0xFFF1F2F6),
                      child: const Icon(
                        Icons.image_outlined,
                        color: Colors.grey,
                      ),
                    ))
                : Image.network(imageUrl, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 16),
        OrderMessageBuyerButton(order: order, brand: brand),
      ],
    );
  }
}

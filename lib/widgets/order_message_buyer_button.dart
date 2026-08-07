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

  static Future<void> open(BuildContext context, OrderItem order) async {
    final buyerUid = (order.customerUid ?? '').trim();
    final sellerUid = (order.merchantUid ?? '').trim();
    final peerName = (order.customerName ?? '').trim().isEmpty
        ? 'Buyer'
        : order.customerName!.trim();

    if (buyerUid.isEmpty) {
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
          await BackendChatService.getUserIdByFirebaseUidValidated(buyerUid);
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
          peerName: peerName,
        );
        chatId = chat.id;
      }

      final productContext = ChatProductContext(
        productId: order.id,
        name: order.itemName,
        image: order.itemImage.isEmpty ? null : order.itemImage,
        price: order.price.toDouble(),
        description: 'Order ${order.orderNumber}',
        merchantId: sellerUid.isEmpty ? null : sellerUid,
      );

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MessagePageBackendApi(
            peerId: chatId,
            peerName: peerName,
            productContext: productContext,
            peerMerchantId: sellerUid.isEmpty ? null : sellerUid,
            peerUserId: peerUserId,
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

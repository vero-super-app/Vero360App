import 'package:flutter/material.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';

/// Food-only checkout. Delivery is Vero Courier and Lilongwe-only
/// (buyer drop-off and restaurant must both be in Lilongwe).
class FoodCheckoutPage extends StatelessWidget {
  const FoodCheckoutPage({super.key, required this.items});

  final List<CartModel> items;

  @override
  Widget build(BuildContext context) {
    final food = items.where((e) => e.isFood).toList();
    if (food.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFFFF8A00),
          foregroundColor: Colors.white,
          title: const Text(
            'Food checkout',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No food items to checkout.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return CheckoutFromCartPage.food(items: food);
  }
}

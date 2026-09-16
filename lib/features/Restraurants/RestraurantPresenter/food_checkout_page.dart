import 'package:flutter/material.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_service.dart';

/// Food-only checkout. Delivery is Vero Courier and Lilongwe-only
/// (buyer drop-off and restaurant must both be in Lilongwe).
class FoodCheckoutPage extends StatefulWidget {
  const FoodCheckoutPage({super.key, required this.items});

  final List<CartModel> items;

  @override
  State<FoodCheckoutPage> createState() => _FoodCheckoutPageState();
}

class _FoodCheckoutPageState extends State<FoodCheckoutPage> {
  List<CartModel>? _prepared;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _prepareItems();
  }

  Future<void> _prepareItems() async {
    final food = widget.items.where((e) => e.isFood).toList();
    if (food.isEmpty) {
      if (mounted) {
        setState(() {
          _prepared = const [];
          _loading = false;
        });
      }
      return;
    }

    final synced = await FoodService().applyStockCapsToCartLines(food);
    if (!mounted) return;
    setState(() {
      _prepared = synced;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
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
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final food = _prepared ?? const <CartModel>[];
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

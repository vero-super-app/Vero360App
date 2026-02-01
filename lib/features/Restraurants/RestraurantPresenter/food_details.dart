import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/features/Restraurants/Models/food_model.dart';
import 'package:vero360_app/GernalServices/address_service.dart';
import 'package:vero360_app/GeneralModels/address_model.dart';

const Color _brandOrange = Color(0xFFFF8A00);
const Color _brandSoft = Color(0xFFFFE8CC);

class FoodDetailsPage extends StatefulWidget {
  final FoodModel foodItem;

  const FoodDetailsPage({required this.foodItem, Key? key}) : super(key: key);

  @override
  State<FoodDetailsPage> createState() => _FoodDetailsPageState();
}

class _FoodDetailsPageState extends State<FoodDetailsPage> {
  // Guest form controllers
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _descriptionCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();

  // Logged-in detection + defaults
  bool _isLoadingDefaults = true;
  bool _isLoggedIn = false;
  String? _defaultName;
  String? _defaultPhone;
  String? _defaultLocation; // will come from default Address description+city

  final AddressService _addressService = AddressService();

  // Gallery / slideshow
  late final PageController _pageController;
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadUserDefaults();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _descriptionCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserDefaults() async {
    try {
      final sp = await SharedPreferences.getInstance();

      // 1) Detect token (logged-in or not)
      final token = sp.getString('jwt_token') ??
          sp.getString('token') ??
          sp.getString('jwt');

      if (token == null || token.isEmpty) {
        // Guest user – no addresses call
        setState(() {
          _isLoggedIn = false;
          _isLoadingDefaults = false;
        });
        return;
      }

      // 2) Pull user details from SharedPreferences
      final name = sp.getString('user_full_name') ?? sp.getString('name');
      final phone = sp.getString('user_phone') ?? sp.getString('phone');

      // 3) Pull default address from backend via AddressService
      String? location;
      try {
        final List<Address> addresses =
            await _addressService.getMyAddresses();

        Address? defaultAddr;
        if (addresses.isNotEmpty) {
          // Prefer isDefault == true if available, otherwise first item
          defaultAddr = addresses.firstWhere(
            (a) => a.isDefault == true,
            orElse: () => addresses.first,
          );
        }

        if (defaultAddr != null) {
          final desc = (defaultAddr.description ?? '').trim();
          final city = (defaultAddr.city ?? '').trim();

          if (desc.isNotEmpty && city.isNotEmpty) {
            location = '$desc, $city';
          } else if (desc.isNotEmpty) {
            location = desc;
          } else if (city.isNotEmpty) {
            location = city;
          }
        }
      } catch (_) {
        // If address fetch fails, just continue with name/phone only
      }

      setState(() {
        _isLoggedIn = true;
        _defaultName = name;
        _defaultPhone = phone;
        _defaultLocation = location;

        // pre-fill text fields too (in case we fall back to form)
        if (name != null && name.trim().isNotEmpty) {
          _nameCtrl.text = name;
        }
        if (phone != null && phone.trim().isNotEmpty) {
          _phoneCtrl.text = phone;
        }
        if (location != null && location.trim().isNotEmpty) {
          _locationCtrl.text = location;
        }

        _isLoadingDefaults = false;
      });
    } catch (_) {
      setState(() {
        _isLoggedIn = false;
        _isLoadingDefaults = false;
      });
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
      ),
    );
  }

  Future<void> _placeOrder() async {
    final item = widget.foodItem;

    String? name;
    String? phone;
    String? location;

    final canUseDefaults = _isLoggedIn &&
        _defaultName != null &&
        _defaultPhone != null &&
        _defaultLocation != null &&
        _defaultName!.trim().isNotEmpty &&
        _defaultPhone!.trim().isNotEmpty &&
        _defaultLocation!.trim().isNotEmpty;

    if (canUseDefaults) {
      // ✅ Logged-in user with default address – no need to fill details
      name = _defaultName!;
      phone = _defaultPhone!;
      location = _defaultLocation!;
    } else {
      // Guest OR logged user without full defaults: validate form
      if (!_formKey.currentState!.validate()) {
        _showSnack('Please fill in all required details.');
        return;
      }

      name = _nameCtrl.text.trim();
      phone = _phoneCtrl.text.trim();
      location = _locationCtrl.text.trim();
    }

    final description = _descriptionCtrl.text.trim();

    // TODO: integrate with your backend order endpoint
    // Example payload (you can send this to NestJS):
    // {
    //   foodId: item.id,
    //   description,
    //   customerName: name,
    //   customerPhone: phone,
    //   deliveryLocation: location
    // }

    _showSnack(
      'Order placed for ${item.FoodName}.\n'
      'Name: $name\n'
      'Phone: $phone\n'
      'Location: $location',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDefaults) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final item = widget.foodItem;
    // use gallery from FoodModel if present, otherwise fallback to main image
    final List<String> images =
        (item.gallery.isNotEmpty ? item.gallery : [item.FoodImage]);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Food Details"),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- IMAGE SLIDESHOW ----------
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: images.length,
                      onPageChanged: (index) {
                        setState(() => _currentImageIndex = index);
                      },
                      itemBuilder: (context, index) {
                        final url = images[index];
                        return ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(18),
                            bottomRight: Radius.circular(18),
                          ),
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => Container(
                              color: Colors.grey.shade200,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image, size: 48),
                            ),
                          ),
                        );
                      },
                    ),

                    // gradient overlay
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(18),
                            bottomRight: Radius.circular(18),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.45),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // dots indicator
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(images.length, (i) {
                          final isActive = i == _currentImageIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 6,
                            width: isActive ? 18 : 6,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ---------- DETAILS CARD ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 18,
                        spreadRadius: 1,
                        color: Colors.black.withOpacity(0.05),
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + price
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.FoodName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _brandSoft,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'MWK ${item.price.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _brandOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Restaurant
                      Text(
                        "From: ${item.RestrauntName}",
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (item.description != null &&
                          item.description!.trim().isNotEmpty)
                        Text(
                          item.description!.trim(),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ---------- CUSTOMER DETAILS ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Order Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Always allow note
                    _buildTextField(
                      controller: _descriptionCtrl,
                      label: 'Add a note to the kitchen (optional)',
                      hintText: 'e.g. No onions, extra cheese…',
                      maxLines: 2,
                      isRequired: false,
                    ),
                    const SizedBox(height: 12),

                    if (_isLoggedIn &&
                        _defaultName != null &&
                        _defaultPhone != null &&
                        _defaultLocation != null &&
                        _defaultName!.trim().isNotEmpty &&
                        _defaultPhone!.trim().isNotEmpty &&
                        _defaultLocation!.trim().isNotEmpty)
                      _LoggedInSummaryCard(
                        name: _defaultName!,
                        phone: _defaultPhone!,
                        location: _defaultLocation!,
                      )
                    else ...[
                      _buildTextField(
                        controller: _nameCtrl,
                        label: 'Your Name',
                        hintText: 'Who is this order for?',
                        isRequired: true,
                      ),
                      const SizedBox(height: 8),
                      _buildTextField(
                        controller: _phoneCtrl,
                        label: 'Your Phone Number',
                        hintText: 'e.g. +265 99 123 4567',
                        keyboardType: TextInputType.phone,
                        isRequired: true,
                      ),
                      const SizedBox(height: 8),
                      _buildTextField(
                        controller: _locationCtrl,
                        label: 'Delivery Location',
                        hintText: 'Area / street / landmarks…',
                        maxLines: 2,
                        isRequired: true,
                      ),
                    ],
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _brandOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: _placeOrder,
                        child: const Text('Place Order'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool isRequired = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (isRequired)
              const Text(
                ' *',
                style: TextStyle(color: Colors.red, fontSize: 13),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.black12, width: 1),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: _brandOrange, width: 2),
            ),
          ),
          validator: isRequired
              ? (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return '$label is required';
                  return null;
                }
              : null,
        ),
      ],
    );
  }
}

// ---------- summary card for logged-in user with default address ----------

class _LoggedInSummaryCard extends StatelessWidget {
  final String name;
  final String phone;
  final String location;

  const _LoggedInSummaryCard({
    required this.name,
    required this.phone,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _brandSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _brandOrange.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.person_pin_circle,
              color: _brandOrange, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deliver to (default address)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  phone,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  location,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// lib/Pages/bike_page.dart
import 'package:flutter/material.dart';

class BikePage extends StatefulWidget {
  const BikePage({super.key});

  @override
  State<BikePage> createState() => _BikePageState();
}

class _BikePageState extends State<BikePage> {
  final _pickup = TextEditingController();
  final _dropoff = TextEditingController();

  @override
  void dispose() {
    _pickup.dispose();
    _dropoff.dispose();
    super.dispose();
  }

  // --- THEME ---
  static const _brandOrange = Color(0xFFFF8A00);
  static const _brandOrangeSoft = Color(0xFFFFE3C2);

  // --- ESTIMATION HELPERS (mock distance; replace with real API later) ---
  int _pseudoKm(String a, String b) {
    final s = (a.trim() + b.trim());
    if (s.isEmpty) return 0;
    final code = s.codeUnits.fold<int>(0, (acc, v) => (acc + v) % 1000);
    return 2 + (code % 12); // 2..13 km
  }

  int _bikePriceMwk(int km) {
    // Example pricing: base 2,000 + 450/km
    return 2000 + (km * 450);
  }

  String _money(int amount) {
    final s = amount.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final rev = s.length - i;
      buf.write(s[i]);
      if (rev > 1 && rev % 3 == 1) buf.write(',');
    }
    return 'MK ${buf.toString()}';
  }

  void _onEstimate() {
    FocusScope.of(context).unfocus();
    final km = _pseudoKm(_pickup.text, _dropoff.text);
    if (km == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter pickup and drop-off to estimate.')),
      );
      return;
    }
    final price = _bikePriceMwk(km);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text('Estimated Fare', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${_money(price)}  •  ~${km} km',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _brandOrange,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'This is an instant estimate. Final price may adjust based on exact route & traffic.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _onBook,
                icon: const Icon(Icons.pedal_bike_rounded),
                label: const Text('Book Bike'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: _brandOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onBook() {
    if (_pickup.text.isEmpty || _dropoff.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill pickup and drop-off.')),
      );
      return;
    }
    final km = _pseudoKm(_pickup.text, _dropoff.text);
    final price = _bikePriceMwk(km);
    // TODO: call your backend create-ride endpoint here
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bike booked! ${_money(price)} • ~${km} km')),
    );
    Navigator.of(context).maybePop();
  }

  InputDecoration _decor(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      // Black border before active (requested)
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.black87, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _brandOrange, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.red.shade600, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_brandOrangeSoft, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // AppBar substitute (modern)
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.pedal_bike_rounded, color: _brandOrange, size: 28),
                    const SizedBox(width: 8),
                    Text('Request a Bike', style: titleStyle),
                  ],
                ),
                const SizedBox(height: 16),

                // Card
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _pickup,
                          textInputAction: TextInputAction.next,
                          decoration: _decor('Pickup location', Icons.my_location_rounded, hint: 'e.g. Vero’s Guest House'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _dropoff,
                          textInputAction: TextInputAction.done,
                          decoration: _decor('Drop-off location', Icons.place_rounded, hint: 'e.g. Gateway Mall'),
                        ),
                        const SizedBox(height: 6),

                        // Small helper “quick service” pill area (optional space for you to tweak)
                        // -------------------------------------------
                        // TODO: adjust spacing/text as you like:
                        // const SizedBox(height: 6),
                        // Align(
                        //   alignment: Alignment.centerLeft,
                        //   child: Text('Quick service • no login needed',
                        //       style: TextStyle(fontSize: 12, color: Colors.black54)),
                        // ),
                        // -------------------------------------------

                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _onEstimate,
                                icon: const Icon(Icons.calculate_rounded),
                                label: const Text('Estimate price'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  side: const BorderSide(color: Colors.black87, width: 1),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _onBook,
                                icon: const Icon(Icons.check_circle_rounded),
                                label: const Text('Book bike'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  backgroundColor: _brandOrange,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                // Mini info card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101010).withOpacity(0.03),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.info_outline_rounded, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('Safe • Fast • Affordable — perfect for quick errands.',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

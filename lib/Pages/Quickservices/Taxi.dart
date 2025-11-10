import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class TaxiPage extends StatefulWidget {
  const TaxiPage({super.key});

  @override
  State<TaxiPage> createState() => _TaxiPageState();
}

class _TaxiPageState extends State<TaxiPage> {
  final _pickup = TextEditingController();
  final _dropoff = TextEditingController();
  TimeOfDay? _pickupTime; // null = ASAP
  bool _mixRide = false;  // false = Solo, true = Mix

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
    return 3 + (code % 15); // 3..17 km
  }

  int _taxiPriceMwk(int km, {required bool mix}) {
    // Example pricing: base 4,000 + 650/km; Mix Ride gets ~20% off
    var price = 4000 + (km * 650);
    if (mix) price = (price * 0.8).round();
    return price;
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

  String _timeLabel() {
    if (_pickupTime == null) return 'ASAP (now)';
    final h = _pickupTime!.hourOfPeriod == 0 ? 12 : _pickupTime!.hourOfPeriod;
    final m = _pickupTime!.minute.toString().padLeft(2, '0');
    final period = _pickupTime!.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  Future<void> _pickTime() async {
    final now = TimeOfDay.now();
    final t = await showTimePicker(
      context: context,
      initialTime: now,
      helpText: 'Pickup time',
      builder: (context, child) {
        // Slight on-brand accent
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: _brandOrange),
          ),
          child: child!,
        );
      },
    );
    if (!mounted) return;
    setState(() => _pickupTime = t);
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
    final price = _taxiPriceMwk(km, mix: _mixRide);
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
              '${_money(price)}  •  ~${km} km • ${_mixRide ? 'Mix Ride' : 'Solo Ride'}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _brandOrange,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Pickup: ${_timeLabel()}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black87),
            ),
            const SizedBox(height: 16),
            Text(
              'This is an instant estimate. Final price may adjust based on exact route, traffic, and wait time.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  void _onFindCar() {
    if (_pickup.text.isEmpty || _dropoff.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill pickup and drop-off.')),
      );
      return;
    }
    FocusScope.of(context).unfocus();

    // Open the live “search / assign / track” sheet
    showModalBottomSheet<RideResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withOpacity(0.25),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RideSearchSheet(
        pickupLabel: _pickup.text,
        dropoffLabel: _dropoff.text,
        pickupTimeLabel: _timeLabel(),
        isMix: _mixRide,
        brandOrange: _brandOrange,
        onDone: (res) {
          // Optional callback once completed/cancelled
          if (res.status == RideResultStatus.completed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Trip completed • ${_money(res.fareMwk ?? 0)} • ${res.distanceKm?.toStringAsFixed(1)} km')),
            );
          } else if (res.status == RideResultStatus.cancelled) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Search cancelled')),
            );
          }
        },
      ),
    );
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
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
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
                // Header
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.local_taxi_rounded, color: _brandOrange, size: 28),
                    const SizedBox(width: 8),
                    Text('Vero Ride (Taxi)', style: titleStyle),
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
                        // Ride type: Solo vs Mix
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                selected: !_mixRide,
                                onSelected: (_) => setState(() => _mixRide = false),
                                label: const Text('Solo ride'),
                                avatar: const Icon(Icons.person_rounded, size: 18),
                                selectedColor: _brandOrange.withOpacity(.15),
                                side: const BorderSide(color: Colors.black87, width: 1),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ChoiceChip(
                                selected: _mixRide,
                                onSelected: (_) => setState(() => _mixRide = true),
                                label: const Text('Mix ride'),
                                avatar: const Icon(Icons.groups_rounded, size: 18),
                                selectedColor: _brandOrange.withOpacity(.15),
                                side: const BorderSide(color: Colors.black87, width: 1),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        TextField(
                          controller: _pickup,
                          textInputAction: TextInputAction.next,
                          decoration: _decor('Pickup location', Icons.my_location_rounded, hint: 'e.g. Area 43, Lilongwe'),
                        ),
                        const SizedBox(height: 12),

                        // Pickup time
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickTime,
                                icon: const Icon(Icons.schedule_rounded),
                                label: Text('Pickup time: ${_timeLabel()}'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  side: const BorderSide(color: Colors.black87, width: 1),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  foregroundColor: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: _dropoff,
                          textInputAction: TextInputAction.done,
                          decoration: _decor('Drop-off location', Icons.place_rounded, hint: 'e.g. Old Town Mall'),
                        ),

                        const SizedBox(height: 16),
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
                                onPressed: _onFindCar,
                                icon: const Icon(Icons.search_rounded),
                                label: const Text('Find car'),
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
                        child: Text('Solo = private ride • Mix = shared fare with other riders.',
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

/* ────────────────────────────────────────────────────────────────────────── */
/*                          RIDE SEARCH / TRACKING UI                        */
/* ────────────────────────────────────────────────────────────────────────── */

enum RidePhase { searching, candidate, assigned, arrived, inProgress, completed, failed, cancelled }

class RideResult {
  final RideResultStatus status;
  final int? fareMwk;
  final double? distanceKm;
  const RideResult({required this.status, this.fareMwk, this.distanceKm});
}

enum RideResultStatus { completed, cancelled }

class RideSearchSheet extends StatefulWidget {
  final String pickupLabel;
  final String dropoffLabel;
  final String pickupTimeLabel;
  final bool isMix;
  final Color brandOrange;
  final void Function(RideResult) onDone;

  const RideSearchSheet({
    super.key,
    required this.pickupLabel,
    required this.dropoffLabel,
    required this.pickupTimeLabel,
    required this.isMix,
    required this.brandOrange,
    required this.onDone,
  });

  @override
  State<RideSearchSheet> createState() => _RideSearchSheetState();
}

class _RideSearchSheetState extends State<RideSearchSheet> with TickerProviderStateMixin {
  RidePhase _phase = RidePhase.searching;
  double _radiusKm = 1.5;
  int _checked = 0;

  // Mock candidate/assignment
  Map<String, dynamic>? _candidate; // {driver, plate, eta, rating, color, model}
  String? _rideId;
  int _etaMin = 0;

  // Tracking animation (mock "map")
  late AnimationController _carController;
  Timer? _searchTicker;
  Timer? _progressTicker;

  @override
  void initState() {
    super.initState();
    _carController = AnimationController(vsync: this, duration: const Duration(seconds: 18));
    _startSearchingMock();
  }

  @override
  void dispose() {
    _searchTicker?.cancel();
    _progressTicker?.cancel();
    _carController.dispose();
    super.dispose();
  }

  void _startSearchingMock() {
    // Simulate expanding search
    _phase = RidePhase.searching;
    _radiusKm = 1.5;
    _checked = 0;

    _searchTicker?.cancel();
    _searchTicker = Timer.periodic(const Duration(milliseconds: 900), (t) {
      setState(() {
        _radiusKm += 1.3;
        _checked += 3 + (math.Random().nextInt(3));
      });
      if (_radiusKm >= 7.0) {
        t.cancel();
        // Found a candidate
        setState(() {
          _phase = RidePhase.candidate;
          _candidate = {
            "driver": "Gift Banda",
            "plate": "BZ 4321",
            "rating": 4.8,
            "eta": 6,
            "model": "Toyota Axio",
            "color": "Silver",
          };
        });
      }
    });
  }

  void _confirmCandidate() {
    // hold/assign
    setState(() {
      _phase = RidePhase.assigned;
      _rideId = "R-${DateTime.now().millisecondsSinceEpoch}";
      _etaMin = _candidate?["eta"] ?? 6;
    });

    // Begin "driver en route" animation
    _carController.reset();
    _carController.forward();

    // Simulate arrival after some time
    _progressTicker?.cancel();
    _progressTicker = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() => _phase = RidePhase.arrived);
      // Start trip shortly after arrival
      _progressTicker = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _phase = RidePhase.inProgress);

        // Complete trip later
        _progressTicker = Timer(const Duration(seconds: 8), () {
          if (!mounted) return;
          setState(() => _phase = RidePhase.completed);
        });
      });
    });
  }

  void _cancelAll() {
    setState(() => _phase = RidePhase.cancelled);
    widget.onDone(const RideResult(status: RideResultStatus.cancelled));
    Navigator.of(context).maybePop();
  }

  void _closeIfDone() {
    if (_phase == RidePhase.completed) {
      // Mock summary values
      final distanceKm = 8.7;
      final fare = 4000 + (distanceKm * 650).round();
      widget.onDone(RideResult(status: RideResultStatus.completed, fareMwk: fare, distanceKm: distanceKm));
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) {
        return SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(t),
              const SizedBox(height: 12),
              _tripSummaryCard(t),
              const SizedBox(height: 12),
              _contentBody(t),
              const SizedBox(height: 16),
              _bottomActions(t),
            ],
          ),
        );
      },
    );
  }

  Widget _header(ThemeData t) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: widget.brandOrange.withOpacity(.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black87, width: 1),
          ),
          child: const Icon(Icons.local_taxi_rounded, size: 22),
        ),
        const SizedBox(width: 10),
        Text(
          _phase == RidePhase.searching
              ? 'Searching for nearby cars'
              : _phase == RidePhase.candidate
                  ? 'Driver found'
                  : _phase == RidePhase.assigned
                      ? 'Driver on the way'
                      : _phase == RidePhase.arrived
                          ? 'Driver has arrived'
                          : _phase == RidePhase.inProgress
                              ? 'Trip in progress'
                              : _phase == RidePhase.completed
                                  ? 'Trip completed'
                                  : _phase == RidePhase.failed
                                      ? 'No cars found'
                                      : 'Cancelled',
          style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _tripSummaryCard(ThemeData t) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black87, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.radio_button_checked, size: 18, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.pickupLabel)),
            const SizedBox(width: 12),
            const Icon(Icons.arrow_downward_rounded, size: 18),
            const SizedBox(width: 12),
            const Icon(Icons.place_rounded, size: 18, color: Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.dropoffLabel)),
          ],
        ),
      ),
    );
  }

  Widget _contentBody(ThemeData t) {
    switch (_phase) {
      case RidePhase.searching:
        return _searchingCard(t);
      case RidePhase.candidate:
        return _candidateCard(t);
      case RidePhase.assigned:
      case RidePhase.arrived:
      case RidePhase.inProgress:
      case RidePhase.completed:
        return _trackingCard(t);
      case RidePhase.failed:
      case RidePhase.cancelled:
        return _failedCard(t);
    }
  }

  Widget _searchingCard(ThemeData t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black87, width: 1),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          SizedBox(
            height: 64,
            width: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 64,
                  width: 64,
                  child: CircularProgressIndicator(
                    strokeWidth: 6,
                    valueColor: AlwaysStoppedAnimation(widget.brandOrange),
                  ),
                ),
                const Icon(Icons.search_rounded, size: 26),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Searching nearby cars…', style: t.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('Radius ~ ${_radiusKm.toStringAsFixed(1)} km • checked $_checked drivers',
              style: t.textTheme.bodySmall?.copyWith(color: Colors.black54)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            minHeight: 6,
            value: (_radiusKm / 10).clamp(0.0, 1.0),
            backgroundColor: Colors.black12,
            valueColor: AlwaysStoppedAnimation(widget.brandOrange),
          ),
          const SizedBox(height: 12),
          Text('Pickup: ${widget.pickupTimeLabel} • ${widget.isMix ? 'Mix ride' : 'Solo ride'}',
              style: t.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _candidateCard(ThemeData t) {
    final c = _candidate!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black87, width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: widget.brandOrange.withOpacity(.15),
                child: const Icon(Icons.person_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['driver'], style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${c['model']} • ${c['color']} • Plate ${c['plate']}',
                        style: t.textTheme.bodySmall?.copyWith(color: Colors.black87)),
                  ],
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
                  Text('${c['rating']}', style: t.textTheme.bodyMedium),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.timer_rounded, size: 18),
              const SizedBox(width: 6),
              Text('ETA ~ ${c['eta']} min', style: t.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _cancelAll,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Decline'),
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
                  onPressed: _confirmCandidate,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('Confirm driver'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: widget.brandOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trackingCard(ThemeData t) {
    final statusText = _phase == RidePhase.assigned
        ? 'Driver is on the way'
        : _phase == RidePhase.arrived
            ? 'Driver has arrived'
            : _phase == RidePhase.inProgress
                ? 'Trip in progress'
                : 'Trip completed';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black87, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_rideId != null)
            Text('Ride: $_rideId', style: t.textTheme.labelMedium?.copyWith(color: Colors.black54)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.traffic_rounded),
              const SizedBox(width: 8),
              Text(statusText, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_phase == RidePhase.assigned) Text('ETA ~ $_etaMin min'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black26),
                ),
                child: Stack(
                  children: [
                    const _MiniGrid(),
                    // Fake route line
                    CustomPaint(
                      painter: _RoutePainter(),
                      size: Size.infinite,
                    ),
                    // Moving car icon
                    AnimatedBuilder(
                      animation: _carController,
                      builder: (context, _) {
                        final p = Curves.easeInOut.transform(_carController.value);
                        final pos = _bezier(Offset(20, 150), const Offset(180, 40), const Offset(330, 130), p);
                        return Positioned(
                          left: pos.dx,
                          top: pos.dy,
                          child: const Icon(Icons.directions_car_rounded, size: 22),
                        );
                      },
                    ),
                    // Start & end pins
                    const Positioned(left: 16, bottom: 12, child: Icon(Icons.radio_button_checked, color: Colors.green)),
                    const Positioned(right: 16, top: 16, child: Icon(Icons.place_rounded, color: Colors.redAccent)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_phase == RidePhase.completed)
            _receipt(t)
          else
            Text(
              'Pickup: ${widget.pickupTimeLabel} • ${widget.isMix ? 'Mix ride' : 'Solo ride'}',
              style: t.textTheme.bodySmall?.copyWith(color: Colors.black87),
            ),
        ],
      ),
    );
  }

  Widget _failedCard(ThemeData t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black87, width: 1),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, size: 40, color: Colors.redAccent),
          const SizedBox(height: 10),
          Text('No cars available right now.', style: t.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('Try changing pickup, widening search, or switching to Mix ride.',
              style: t.textTheme.bodySmall?.copyWith(color: Colors.black54), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _receipt(ThemeData t) {
    // Mock numbers
    const distanceKm = 8.7;
    final fare = 4000 + (distanceKm * 650).round();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.brandOrange.withOpacity(.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black87, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trip summary', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _kv('Distance', '${distanceKm.toStringAsFixed(1)} km', t),
          _kv('Fare', 'MK ${fare.toString()}', t),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, ThemeData t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(k, style: t.textTheme.bodySmall?.copyWith(color: Colors.black54))),
          Text(v, style: t.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _bottomActions(ThemeData t) {
    if (_phase == RidePhase.searching) {
      return OutlinedButton.icon(
        onPressed: _cancelAll,
        icon: const Icon(Icons.close_rounded),
        label: const Text('Cancel search'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: Colors.black87, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    } else if (_phase == RidePhase.candidate) {
      // actions inside candidate card already
      return const SizedBox.shrink();
    } else if (_phase == RidePhase.completed) {
      return ElevatedButton.icon(
        onPressed: _closeIfDone,
        icon: const Icon(Icons.check_rounded),
        label: const Text('Done'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: widget.brandOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    } else {
      return OutlinedButton.icon(
        onPressed: _cancelAll,
        icon: const Icon(Icons.cancel_rounded),
        label: const Text('Cancel ride'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: Colors.black87, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  // Simple quadratic bezier between three points
  Offset _bezier(Offset p0, Offset p1, Offset p2, double t) {
    final x = (1 - t) * (1 - t) * p0.dx + 2 * (1 - t) * t * p1.dx + t * t * p2.dx;
    final y = (1 - t) * (1 - t) * p0.dy + 2 * (1 - t) * t * p1.dy + t * t * p2.dy;
    return Offset(x, y);
  }
}

/* ───────────────────────────── Helper painters/widgets ───────────────────── */

class _MiniGrid extends StatelessWidget {
  const _MiniGrid();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(),
      size: Size.infinite,
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(20, size.height - 30)
      ..quadraticBezierTo(size.width * .55, 40, size.width - 20, 20 + 110);
    final paint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

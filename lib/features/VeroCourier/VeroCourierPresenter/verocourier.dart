import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/VeroCourier/Model/courier.models.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/courier_onboarding_page.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/courier_widgets.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierService/vero_courier_service.dart';

class VerocourierPage extends StatefulWidget {
  const VerocourierPage({super.key});

  @override
  State<VerocourierPage> createState() => _VerocourierPageState();
}

class _VerocourierPageState extends State<VerocourierPage> {
  static const _onboardingDoneKey = 'courier_onboarding_done';
  static const _veroOrange = Color(0xFFFF8A00);
  static const _skyBlue = Color(0xFF2D9CDB);
  static const _mintGreen = Color(0xFF27AE60);
  static const _violet = Color(0xFF9B51E0);
  static const _rose = Color(0xFFEB5757);

  final _formKey = GlobalKey<FormState>();
  final _pickupCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _additionalCtrl = TextEditingController();
  final _trackCtrl = TextEditingController();
  final _senderNameCtrl = TextEditingController();
  final _senderPhoneCtrl = TextEditingController();
  final _senderAddressCtrl = TextEditingController();
  final _recipientNameCtrl = TextEditingController();
  final _recipientPhoneCtrl = TextEditingController();
  final _recipientAddressCtrl = TextEditingController();

  final CourierService _courierService = const CourierService();
  List<CourierDelivery> _deliveries = const [];
  CourierDelivery? _trackingResult;
  int? _trackedDeliveryId;
  Timer? _progressPollingTimer;
  String _senderName = '';
  String _senderPhone = '';
  String _senderCity = '';
  String? _selectedGoodsType;
  int _selectedService = 0;
  bool _loadingSendingDetails = true;
  bool _detectingCity = true;
  bool _citySupported = true;
  String _detectedCity = '';
  bool _loadingParcelForm = false;
  bool _submitting = false;
  bool _loadingList = false;
  bool _tracking = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
    _loadSenderInfo();
    _detectAndValidateCity();
  }

  Future<void> _onServiceTabChanged(int index) async {
    setState(() => _selectedService = index);
    if (index == 1) {
      setState(() => _loadingParcelForm = true);
      Future<void>.delayed(const Duration(milliseconds: 260), () {
        if (!mounted) return;
        setState(() => _loadingParcelForm = false);
      });
    }
    if (index == 3 && _deliveries.isEmpty) {
      await _loadDeliveries();
    }
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_onboardingDoneKey) ?? false;
    if (!mounted || completed) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const CourierOnboardingPage(),
        fullscreenDialog: true,
      ),
    );
    await prefs.setBool(_onboardingDoneKey, done == true);
  }

  Future<void> _loadSenderInfo() async {
    if (mounted) {
      setState(() => _loadingSendingDetails = true);
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _senderName =
          (prefs.getString('fullName') ??
                  prefs.getString('name') ??
                  'Vero User')
              .trim();
      _senderPhone = (prefs.getString('phone') ?? '').trim();
      _senderCity = (prefs.getString('city') ?? 'Lilongwe').trim();
      _senderNameCtrl.text = _senderName;
      _senderPhoneCtrl.text = _senderPhone;
      _senderAddressCtrl.text = _senderCity;
      _loadingSendingDetails = false;
    });
  }

  Future<void> _detectAndValidateCity() async {
    setState(() => _detectingCity = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _detectingCity = false;
          _citySupported = false;
          _detectedCity = 'Unknown';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _detectingCity = false;
          _citySupported = false;
          _detectedCity = 'Unknown';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      final place = placemarks.isNotEmpty ? placemarks.first : null;
      final rawCity = (place?.locality?.trim().isNotEmpty == true
              ? place!.locality!
              : (place?.subAdministrativeArea?.trim().isNotEmpty == true
                  ? place!.subAdministrativeArea!
                  : (place?.administrativeArea ?? 'Unknown')))
          .trim();

      final normalized = rawCity.toLowerCase();
      final supported = normalized.contains('lilongwe') ||
          normalized.contains('blantyre') ||
          normalized.contains('zomba');

      if (!mounted) return;
      setState(() {
        _detectingCity = false;
        _citySupported = supported;
        _detectedCity = rawCity;
        if (rawCity.isNotEmpty && rawCity != 'Unknown') {
          _senderCity = rawCity;
          _senderAddressCtrl.text = rawCity;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _detectingCity = false;
        _citySupported = false;
        _detectedCity = 'Unknown';
      });
    }
  }

  @override
  void dispose() {
    _progressPollingTimer?.cancel();
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _descriptionCtrl.dispose();
    _additionalCtrl.dispose();
    _trackCtrl.dispose();
    _senderNameCtrl.dispose();
    _senderPhoneCtrl.dispose();
    _senderAddressCtrl.dispose();
    _recipientNameCtrl.dispose();
    _recipientPhoneCtrl.dispose();
    _recipientAddressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDeliveries() async {
    setState(() => _loadingList = true);
    try {
      final data = await _courierService.getMyDeliveries();
      if (!mounted) return;
      setState(() => _deliveries = data);
    } on ApiException catch (e) {
      _toast(e.message, isError: true);
    } catch (_) {
      _toast('Failed to load courier deliveries.', isError: true);
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _trackDelivery() async {
    final id = int.tryParse(_trackCtrl.text.trim());
    if (id == null) {
      _toast('Enter a valid delivery number.', isError: true);
      return;
    }
    setState(() => _tracking = true);
    try {
      final data = await _courierService.getDeliveryById(id);
      if (!mounted) return;
      setState(() {
        _trackingResult = data;
        _trackedDeliveryId = id;
      });
      _startProgressPolling();
    } on ApiException catch (e) {
      _toast(e.message, isError: true);
      if (mounted) setState(() => _trackingResult = null);
    } catch (_) {
      _toast('Could not track this delivery right now.', isError: true);
      if (mounted) setState(() => _trackingResult = null);
    } finally {
      if (mounted) setState(() => _tracking = false);
    }
  }

  void _startProgressPolling() {
    _progressPollingTimer?.cancel();
    if (_trackedDeliveryId == null) return;
    _progressPollingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || _trackedDeliveryId == null) return;
      try {
        final latest = await _courierService.getDeliveryById(_trackedDeliveryId!);
        if (!mounted) return;
        setState(() => _trackingResult = latest);
      } catch (_) {
        // keep last known state; no noisy toasts during background refresh
      }
    });
  }

  String _statusDisplay(CourierStatus status) {
    switch (status) {
      case CourierStatus.accepted:
        return 'Accepted';
      case CourierStatus.onTheWay:
        return 'Coming';
      case CourierStatus.delivered:
        return 'Delivered';
      case CourierStatus.cancelled:
        return 'Cancelled';
      case CourierStatus.pending:
        return 'Pending';
    }
  }

  Future<void> _submit() async {
    if (!_citySupported) {
      _toast(
        'Sorry, Vero Courier is not available in your city. We are expanding soon.',
        isError: true,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_senderPhone.isEmpty || _senderCity.isEmpty) {
      _toast(
        'Missing sender profile details. Please update your account (name, phone, city).',
        isError: true,
      );
      return;
    }
    _senderName = _senderNameCtrl.text.trim();
    _senderPhone = _senderPhoneCtrl.text.trim();
    _senderCity = _senderAddressCtrl.text.trim().isEmpty
        ? _senderCity
        : _senderAddressCtrl.text.trim();

    setState(() => _submitting = true);
    final mergedAdditionalInfo = [
      _additionalCtrl.text.trim(),
      if (_recipientNameCtrl.text.trim().isNotEmpty)
        'Recipient: ${_recipientNameCtrl.text.trim()}',
      if (_recipientPhoneCtrl.text.trim().isNotEmpty)
        'Recipient Phone: ${_recipientPhoneCtrl.text.trim()}',
      if (_recipientAddressCtrl.text.trim().isNotEmpty)
        'Recipient Address: ${_recipientAddressCtrl.text.trim()}',
    ].where((e) => e.isNotEmpty).join(' | ');

    try {
      final created = await _courierService.createDelivery(
        CreateCourierDeliveryDto(
          courierPhone: _senderPhone,
          courierEmail: 'no-email@vero.local',
          courierCity: _senderCity,
          pickupLocation: _pickupCtrl.text.trim(),
          dropoffLocation: _dropoffCtrl.text.trim(),
          typeOfGoods: _selectedGoodsType,
          descriptionOfGoods: _descriptionCtrl.text.trim(),
          additionalInformation: mergedAdditionalInfo,
        ),
      );
      if (!mounted) return;
      _toast('Delivery created: #${created.courierId}');
      _formKey.currentState?.reset();
      _pickupCtrl.clear();
      _dropoffCtrl.clear();
      _selectedGoodsType = null;
      _descriptionCtrl.clear();
      _additionalCtrl.clear();
      _recipientNameCtrl.clear();
      _recipientPhoneCtrl.clear();
      _recipientAddressCtrl.clear();
      _trackCtrl.text = created.courierId.toString();
      await _onServiceTabChanged(2);
      await _trackDelivery();
      await _loadDeliveries();
    } on ApiException catch (e) {
      _toast(e.message, isError: true);
    } catch (_) {
      _toast('Could not create delivery. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _saveSendingDetails() async {
    if (!_citySupported) {
      _toast(
        'Sorry, Vero Courier is not available in your city. We are expanding soon.',
        isError: true,
      );
      return;
    }
    final missing = <String>[];
    if (_senderNameCtrl.text.trim().isEmpty) missing.add('Sender full name');
    if (_senderPhoneCtrl.text.trim().isEmpty) missing.add('Sender phone number');
    if (_senderAddressCtrl.text.trim().isEmpty) missing.add('Sender address');
    if (_recipientNameCtrl.text.trim().isEmpty) missing.add('Recipient full name');
    if (_recipientPhoneCtrl.text.trim().isEmpty) missing.add('Recipient phone number');
    if (_recipientAddressCtrl.text.trim().isEmpty) missing.add('Recipient address');
    if (missing.isNotEmpty) {
      _toast('Complete all fields first: ${missing.join(', ')}', isError: true);
      return;
    }

    setState(() {
      _senderName = _senderNameCtrl.text.trim();
      _senderPhone = _senderPhoneCtrl.text.trim();
      _senderCity = _senderAddressCtrl.text.trim().isEmpty
          ? _senderCity
          : _senderAddressCtrl.text.trim();
    });
   // _toast('Sending details saved for this session.');
    await _onServiceTabChanged(1);
  }

  Future<void> _updateStatus(CourierDelivery delivery, CourierStatus status) async {
    try {
      await _courierService.updateStatus(id: delivery.courierId, status: status);
      if (!mounted) return;
      _toast('Status updated to ${status.value}.');
      await _loadDeliveries();
    } on ApiException catch (e) {
      _toast(e.message, isError: true);
    } catch (_) {
      _toast('Failed to update status.', isError: true);
    }
  }

  void _toast(String msg, {bool isError = false}) {
    ToastHelper.showCustomToast(
      context,
      msg,
      isSuccess: !isError,
      errorMessage: isError ? msg : '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadDeliveries,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
              child: ColoredBox(
                color: _veroOrange,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.of(context).padding.top + 14,
                    16,
                    18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD18A), Colors.white],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              PhosphorIconsBold.truck,
                              color: _veroOrange,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Vero Courier',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Send parcel with us within your city',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Fast pickup, secure handling, real-time progress updates.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _serviceTypesRow(),
                  const SizedBox(height: 10),
                  if (_detectingCity)
                    const Card(
                      elevation: 0,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text('Detecting your city for courier availability...'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Card(
                      elevation: 0,
                      color: _citySupported
                          ? const Color(0xFFEAF9EF)
                          : const Color(0xFFFFF3F1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: _citySupported
                              ? const Color(0xFFBEE7C8)
                              : const Color(0xFFFFCFC8),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _citySupported
                              ? 'Vero Courier is available in your city: $_detectedCity'
                              : 'Sorry, Vero Courier is not available in your city. We are expanding soon.',
                          style: TextStyle(
                            color: _citySupported
                                ? const Color(0xFF1E7A38)
                                : const Color(0xFFAA3A2A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  ..._activeSectionContent(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    );
  }

  Widget _senderCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFEAEAEA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(PhosphorIconsBold.userCircle, color: _skyBlue, size: 18),
                SizedBox(width: 8),
                Text(
                  "Sender details",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _field(
              _senderNameCtrl,
              'Full Name',
              hint: 'Enter your full name',
            ),
            _field(
              _senderPhoneCtrl,
              'Phone Number',
              hint: 'Enter phone number',
            ),
            _field(
              _senderAddressCtrl,
              'Address',
              hint: 'Enter address',
            ),
          ],
        ),
      ),
    );
  }

  Widget _recipientCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFEAEAEA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(PhosphorIconsBold.identificationBadge, color: _mintGreen, size: 18),
                SizedBox(width: 8),
                Text(
                  "Recipient details",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _field(_recipientNameCtrl, 'Full Name', hint: 'Recipient name'),
            _field(
              _recipientPhoneCtrl,
              'Phone Number',
              hint: 'Recipient phone',
            ),
            _field(
              _recipientAddressCtrl,
              'Address',
              hint: 'Recipient address',
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _activeSectionContent() {
    switch (_selectedService) {
      case 0:
        if (!_citySupported) {
          return [];
        }
        return [
          _sectionTitle('Sending Details'),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _loadingSendingDetails
                ? const _DetailsLoadingCard()
                : Column(
                    key: const ValueKey('sendingDetailsForms'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 420),
                        builder: (context, value, child) => Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, (1 - value) * 10),
                            child: child,
                          ),
                        ),
                        child: _senderCard(),
                      ),
                      const SizedBox(height: 12),
                      _sectionTitle("Recipient's Information"),
                      const SizedBox(height: 8),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 520),
                        builder: (context, value, child) => Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, (1 - value) * 14),
                            child: child,
                          ),
                        ),
                        child: _recipientCard(),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _veroOrange,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _saveSendingDetails,
              icon: const Icon(PhosphorIconsBold.checkCircle, size: 20),
              label: const Text(
                'Next',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ];
      case 1:
        if (!_citySupported) {
          return [];
        }
        const goodsOptions = <String>[
          'Documents',
          'Electronics',
          'Groceries',
          'Food',
          'Clothes',
          'Fragile Item',
          'Other',
        ];
        return [
          _sectionTitle('Send a Parcel'),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _loadingParcelForm
                ? const _ParcelFormLoadingCard()
                : TweenAnimationBuilder<double>(
                    key: const ValueKey('parcelFormContent'),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 480),
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - value) * 14),
                        child: child,
                      ),
                    ),
                    child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: _veroOrange.withValues(alpha: 0.30)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(_pickupCtrl, 'pickupLocation', hint: 'Area 18, House 123'),
                      _field(_dropoffCtrl, 'dropoffLocation', hint: 'City Centre, Shop 45'),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedGoodsType,
                          decoration: InputDecoration(
                            labelText: 'TypeOfGoods',
                            hintText: 'Select goods type',
                            filled: true,
                            fillColor: const Color(0xFFFFFBF4),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: _veroOrange.withValues(alpha: 0.24)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: _veroOrange, width: 1.4),
                            ),
                          ),
                          items: goodsOptions
                              .map(
                                (item) => DropdownMenuItem<String>(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedGoodsType = value),
                        ),
                      ),
                      _field(
                        _descriptionCtrl,
                        'DescriptionOfGoods (optional)',
                        required: false,
                        maxLines: 2,
                      ),
                      _field(
                        _additionalCtrl,
                        'AdditionalInformation (optional)',
                        required: false,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _veroOrange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(PhosphorIconsBold.paperPlaneTilt),
                          label: Text(_submitting ? 'Submitting...' : 'Book Delivery'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
                  ),
          ),
        ];
      case 2:
        if (!_citySupported) {
          return [];
        }
        return [
          _sectionTitle('Progress'),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _violet.withValues(alpha: 0.26)),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFFF8F2FF), Color(0xFFFFFFFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      color: _violet.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(PhosphorIconsBold.magnifyingGlass, color: _violet),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _trackCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Search by delivery number',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _violet,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _tracking ? null : _trackDelivery,
                    child: _tracking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Track'),
                  ),
                ],
              ),
            ),
          ),
          if (_trackingResult != null) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: _violet.withValues(alpha: 0.18)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.clockCounterClockwise, color: _violet, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Live status',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _violet.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusDisplay(_trackingResult!.status),
                        style: const TextStyle(
                          color: _violet,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            CourierDeliveryCard(delivery: _trackingResult!),
          ],
        ];
      default:
        if (!_citySupported) {
          return [];
        }
        return [
          _sectionTitle('Shipping History'),
          const SizedBox(height: 8),
          if (_loadingList)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_deliveries.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFEAEAEA)),
              ),
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: Text('No parcel history yet.'),
              ),
            )
          else
            ..._deliveries.take(20).map(_deliveryCard),
        ];
    }
  }

  Widget _serviceTypesRow() {
    final List<(String, IconData, Color)> services = [
      ('Sending Details', PhosphorIconsBold.package, _skyBlue),
      ('Send a Parcel', PhosphorIconsBold.truck, _mintGreen),
      ('Progress', PhosphorIconsBold.airplaneTakeoff, _violet),
      ('Shipping History', PhosphorIconsBold.clockCounterClockwise, _rose),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < services.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == services.length - 1 ? 0 : 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _onServiceTabChanged(i),
                child: Container(
                  width: 88,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: _selectedService == i
                        ? services[i].$3.withValues(alpha: 0.12)
                        : const Color(0xFFF4F4F6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedService == i
                          ? services[i].$3.withValues(alpha: 0.45)
                          : const Color(0xFFE6E6E8),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        services[i].$2,
                        color: _selectedService == i
                            ? services[i].$3
                            : const Color(0xFF8A8A8A),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        services[i].$1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _selectedService == i
                              ? services[i].$3
                              : const Color(0xFF555555),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _deliveryCard(CourierDelivery d) {
    return CourierDeliveryCard(
      delivery: d,
      footer: Wrap(
        spacing: 8,
        children: CourierStatus.values
            .where((s) => s != d.status)
            .map(
              (s) => ActionChip(
                label: Text(s.value),
                onPressed: () => _updateStatus(d, s),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = true,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFFFFFBF4),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _veroOrange.withValues(alpha: 0.24)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _veroOrange, width: 1.4),
          ),
        ),
      ),
    );
  }
}

class _DetailsLoadingCard extends StatelessWidget {
  const _DetailsLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('detailsLoading'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFEAEAEA)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            _DetailsSkeletonLine(width: 180, height: 14),
            SizedBox(height: 12),
            _DetailsSkeletonLine(width: double.infinity, height: 46),
            SizedBox(height: 10),
            _DetailsSkeletonLine(width: double.infinity, height: 46),
            SizedBox(height: 10),
            _DetailsSkeletonLine(width: double.infinity, height: 46),
          ],
        ),
      ),
    );
  }
}

class _ParcelFormLoadingCard extends StatelessWidget {
  const _ParcelFormLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('parcelLoading'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFEAEAEA)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            _DetailsSkeletonLine(width: double.infinity, height: 46),
            SizedBox(height: 10),
            _DetailsSkeletonLine(width: double.infinity, height: 46),
            SizedBox(height: 10),
            _DetailsSkeletonLine(width: double.infinity, height: 46),
            SizedBox(height: 10),
            _DetailsSkeletonLine(width: double.infinity, height: 72),
            SizedBox(height: 12),
            _DetailsSkeletonLine(width: double.infinity, height: 46),
          ],
        ),
      ),
    );
  }
}

class _DetailsSkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  const _DetailsSkeletonLine({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F1F1),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

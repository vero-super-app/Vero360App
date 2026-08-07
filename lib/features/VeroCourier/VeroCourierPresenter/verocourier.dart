import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/utils/merchant_contact_display.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/VeroCourier/Model/courier.models.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/courier_onboarding_page.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/courier_widgets.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierService/courier_city.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierService/vero_courier_service.dart';

class VerocourierPage extends StatefulWidget {
  const VerocourierPage({super.key});

  @override
  State<VerocourierPage> createState() => _VerocourierPageState();
}

class _VerocourierPageState extends State<VerocourierPage> {
  static const _onboardingDoneKey = 'courier_onboarding_done';
  static const _draftSenderNameKey = 'courier_draft_sender_name';
  static const _draftSenderPhoneKey = 'courier_draft_sender_phone';
  static const _draftSenderAddressKey = 'courier_draft_sender_address';
  static const _draftRecipientNameKey = 'courier_draft_recipient_name';
  static const _draftRecipientPhoneKey = 'courier_draft_recipient_phone';
  static const _draftRecipientAddressKey = 'courier_draft_recipient_address';
  static const _draftCompleteKey = 'courier_draft_complete';
  static const _veroOrange = Color(0xFFFF8A00);
  static const _skyBlue = Color(0xFF2D9CDB);
  static const _mintGreen = Color(0xFF27AE60);
  static const _violet = Color(0xFF9B51E0);
  static const _rose = Color(0xFFEB5757);
  static const _pageBg = Color(0xFFF7F8FA);

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
  String _senderEmail = '';
  String _senderCity = '';
  String? _selectedGoodsType;
  int _selectedService = 0;
  bool _loadingSendingDetails = true;
  bool _detectingCity = true;
  bool _citySupported = true;
  String _detectedCity = '';
  CourierServiceCity? _serviceCity;
  String _cityGateMessage = '';
  bool _loadingParcelForm = false;
  bool _submitting = false;
  bool _loadingList = false;
  bool _tracking = false;
  bool _sendingDetailsComplete = false;
  /// 0 = sender card, 1 = recipient card
  int _sendingStep = 0;
  bool _checkingAuth = true;
  bool _isLoggedIn = false;
  bool _bootstrapped = false;
  StreamSubscription<User?>? _authSub;

  /// Never treat Firebase UIDs / junk as a phone number.
  static String _sanitizePhone(String? raw) {
    final cleaned = (raw ?? '').trim();
    if (cleaned.isEmpty) return '';
    final display = safeMerchantPhone(cleaned);
    return display == 'No phone number' ? '' : cleaned;
  }

  @override
  void initState() {
    super.initState();
    _registerSendingDetailsListeners();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      _checkAuth();
    });
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    if (mounted) setState(() => _checkingAuth = true);

    final user = FirebaseAuth.instance.currentUser;
    String? token;
    if (user != null) {
      token = await AuthHandler.getFirebaseToken();
    }

    final loggedIn =
        user != null && token != null && token.trim().isNotEmpty;

    if (!mounted) return;
    setState(() {
      _checkingAuth = false;
      _isLoggedIn = loggedIn;
    });

    if (loggedIn) {
      await _bootstrapIfNeeded();
    } else {
      _bootstrapped = false;
      _progressPollingTimer?.cancel();
    }
  }

  Future<void> _bootstrapIfNeeded() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    await _checkOnboarding();
    await _loadSenderInfo();
    await _detectAndValidateCity();
    await _loadDeliveries();
  }

  void _registerSendingDetailsListeners() {
    void onSendingFieldChanged() {
      if (!_sendingDetailsComplete) return;
      if (!mounted) return;
      setState(() => _sendingDetailsComplete = false);
    }

    for (final ctrl in [
      _senderNameCtrl,
      _senderPhoneCtrl,
      _senderAddressCtrl,
      _recipientNameCtrl,
      _recipientPhoneCtrl,
      _recipientAddressCtrl,
    ]) {
      ctrl.addListener(onSendingFieldChanged);
    }
  }

  bool _hasValidSendingDetails() {
    return _senderNameCtrl.text.trim().isNotEmpty &&
        _sanitizePhone(_senderPhoneCtrl.text).isNotEmpty &&
        _senderAddressCtrl.text.trim().isNotEmpty &&
        _recipientNameCtrl.text.trim().isNotEmpty &&
        _sanitizePhone(_recipientPhoneCtrl.text).isNotEmpty &&
        _recipientAddressCtrl.text.trim().isNotEmpty;
  }

  bool _canAccessServiceTab(int index) {
    if (index == 0) return true;
    if (!_citySupported) return false;
    if (index == 1) return _sendingDetailsComplete && _hasValidSendingDetails();
  // Progress and history are always reachable once city is supported.
    return true;
  }

  String? _tabAccessMessage(int index) {
    if (!_citySupported) {
      return _cityGateMessage.isNotEmpty
          ? _cityGateMessage
          : 'Vero Courier is not available in your city yet.';
    }
    if (index == 1 && (!_sendingDetailsComplete || !_hasValidSendingDetails())) {
      return 'Complete sending details first, then tap Next.';
    }
    return null;
  }

  String get _serviceCityLabel =>
      _serviceCity != null
          ? CourierCityHelper.displayName(_serviceCity!)
          : (_detectedCity.isNotEmpty ? _detectedCity : 'your city');

  String get _serviceCityCode =>
      _serviceCity != null ? CourierCityHelper.shortCode(_serviceCity!) : '—';

  /// Blocks inter-city addresses (e.g. Zomba → Lilongwe).
  String? _cityConflictFor(String? text, String fieldLabel) {
    final city = _serviceCity;
    if (city == null) return null;
    return CourierCityHelper.conflictMessage(
      text: text,
      requiredCity: city,
      fieldLabel: fieldLabel,
    );
  }

  /// Sender location (profile / address) must match GPS-detected city.
  String? _senderLocationMismatch({String? addressOverride}) {
    final detected = _serviceCity;
    if (detected == null) return null;

    final addressText = addressOverride ?? _senderAddressCtrl.text;
    final addressCity = CourierCityHelper.resolve(addressText);

    // Address explicitly naming another city is not allowed.
    if (addressCity != null && addressCity != detected) {
      return 'Detected area (${CourierCityHelper.displayName(detected)}) must '
          'match your sender location '
          '(${CourierCityHelper.displayName(addressCity)}). '
          'Vero Courier only picks up within ${_serviceCityLabel}.';
    }
    return _cityConflictFor(addressText, 'Sender pickup address');
  }

  String? _validateIntraCityBooking() {
    if (_serviceCity == null) {
      return _cityGateMessage.isNotEmpty
          ? _cityGateMessage
          : 'Could not confirm your city. Enable location and try again.';
    }

    final senderMismatch = _senderLocationMismatch();
    if (senderMismatch != null) return senderMismatch;

    final recipientConflict = _cityConflictFor(
      _recipientAddressCtrl.text,
      'Recipient delivery address',
    );
    if (recipientConflict != null) return recipientConflict;

    final pickupConflict = _cityConflictFor(
      _pickupCtrl.text,
      'Pickup location',
    );
    if (pickupConflict != null) return pickupConflict;

    final dropoffConflict = _cityConflictFor(
      _dropoffCtrl.text,
      'Drop-off location',
    );
    if (dropoffConflict != null) return dropoffConflict;

    return null;
  }

  void _syncParcelLocationsFromSendingDetails() {
    if (_pickupCtrl.text.trim().isEmpty) {
      _pickupCtrl.text = _senderAddressCtrl.text.trim();
    }
    if (_dropoffCtrl.text.trim().isEmpty) {
      _dropoffCtrl.text = _recipientAddressCtrl.text.trim();
    }
  }

  Future<void> _onServiceTabChanged(int index) async {
    if (index == _selectedService) return;

    final blocked = _tabAccessMessage(index);
    if (blocked != null) {
      _toast(blocked, isError: true);
      if (index == 1 && !_sendingDetailsComplete) {
        setState(() => _selectedService = 0);
      }
      return;
    }

    setState(() => _selectedService = index);
    if (index == 1) {
      setState(() => _loadingParcelForm = true);
      Future<void>.delayed(const Duration(milliseconds: 260), () {
        if (!mounted) return;
        setState(() => _loadingParcelForm = false);
      });
    }
    if (index == 2 || index == 3) {
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

    final authPhone = _sanitizePhone(
      FirebaseAuth.instance.currentUser?.phoneNumber,
    );
    final profilePhone = _sanitizePhone(prefs.getString('phone'));
    final draftPhone = _sanitizePhone(prefs.getString(_draftSenderPhoneKey));

    final draftName = (prefs.getString(_draftSenderNameKey) ?? '').trim();
    final draftAddress = (prefs.getString(_draftSenderAddressKey) ?? '').trim();
    final profileName = (prefs.getString('fullName') ??
            prefs.getString('name') ??
            'Vero User')
        .trim();
    final profileCity = (prefs.getString('city') ?? 'Lilongwe').trim();
    final email = (prefs.getString('email') ??
            FirebaseAuth.instance.currentUser?.email ??
            '')
        .trim();

    final recipientName =
        (prefs.getString(_draftRecipientNameKey) ?? '').trim();
    final recipientPhone =
        _sanitizePhone(prefs.getString(_draftRecipientPhoneKey));
    final recipientAddress =
        (prefs.getString(_draftRecipientAddressKey) ?? '').trim();
    final draftComplete = prefs.getBool(_draftCompleteKey) ?? false;

    final resolvedPhone =
        draftPhone.isNotEmpty
            ? draftPhone
            : (profilePhone.isNotEmpty
                ? profilePhone
                : authPhone);
    final resolvedName = draftName.isNotEmpty ? draftName : profileName;
    final resolvedAddress =
        draftAddress.isNotEmpty ? draftAddress : profileCity;

    setState(() {
      _senderName = resolvedName;
      _senderPhone = resolvedPhone;
      _senderEmail = email;
      _senderCity = profileCity;
      _senderNameCtrl.text = resolvedName;
      _senderPhoneCtrl.text = resolvedPhone;
      _senderAddressCtrl.text = resolvedAddress;
      _recipientNameCtrl.text = recipientName;
      _recipientPhoneCtrl.text = recipientPhone;
      _recipientAddressCtrl.text = recipientAddress;
      _sendingDetailsComplete =
          draftComplete && _hasValidSendingDetails();
      _sendingStep = _sendingDetailsComplete ? 1 : 0;
      _loadingSendingDetails = false;
    });
  }

  Future<void> _persistSendingDraft({required bool complete}) async {
    final prefs = await SharedPreferences.getInstance();
    final phone = _sanitizePhone(_senderPhoneCtrl.text);
    await prefs.setString(_draftSenderNameKey, _senderNameCtrl.text.trim());
    await prefs.setString(_draftSenderPhoneKey, phone);
    await prefs.setString(
      _draftSenderAddressKey,
      _senderAddressCtrl.text.trim(),
    );
    await prefs.setString(
      _draftRecipientNameKey,
      _recipientNameCtrl.text.trim(),
    );
    await prefs.setString(
      _draftRecipientPhoneKey,
      _sanitizePhone(_recipientPhoneCtrl.text),
    );
    await prefs.setString(
      _draftRecipientAddressKey,
      _recipientAddressCtrl.text.trim(),
    );
    await prefs.setBool(_draftCompleteKey, complete);
    if (phone.isNotEmpty) {
      await prefs.setString('phone', phone);
    }
  }

  Future<void> _detectAndValidateCity() async {
    setState(() {
      _detectingCity = true;
      _cityGateMessage = '';
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _detectingCity = false;
          _citySupported = false;
          _serviceCity = null;
          _detectedCity = 'Unknown';
          _cityGateMessage =
              'Turn on location so we can confirm your city for same-city courier.';
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
          _serviceCity = null;
          _detectedCity = 'Unknown';
          _cityGateMessage =
              'Allow location access so Vero Courier can match your city '
              '(Lilongwe, Blantyre, or Zomba).';
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

      final detected = CourierCityHelper.resolve(rawCity);

      if (!mounted) return;

      if (detected == null) {
        setState(() {
          _detectingCity = false;
          _citySupported = false;
          _serviceCity = null;
          _detectedCity = rawCity.isEmpty ? 'Unknown' : rawCity;
          _cityGateMessage =
              'Vero Courier is only available in Lilongwe (LLZ), '
              'Blantyre (BTZ), and Zomba — within the same city only.';
        });
        return;
      }

      final canonical = CourierCityHelper.displayName(detected);
      final code = CourierCityHelper.shortCode(detected);
      final addr = _senderAddressCtrl.text.trim();
      final addrCity = CourierCityHelper.resolve(addr);
      final cityOnlyMismatch = addrCity != null &&
          addrCity != detected &&
          addr.toLowerCase() ==
              CourierCityHelper.displayName(addrCity).toLowerCase();

      // Replace bare wrong-city drafts (e.g. "Lilongwe") with detected city.
      final effectiveAddress =
          (addr.isEmpty || cityOnlyMismatch) ? canonical : addr;
      final addressMismatch = CourierCityHelper.conflictMessage(
        text: effectiveAddress,
        requiredCity: detected,
        fieldLabel: 'Sender pickup address',
      );

      setState(() {
        _detectingCity = false;
        _serviceCity = detected;
        _detectedCity = canonical;
        _senderCity = canonical;
        _senderAddressCtrl.text = effectiveAddress;
        _citySupported = addressMismatch == null;
        _cityGateMessage = addressMismatch ??
            'Within $canonical only ($code → $code). '
                'Pickup and delivery must stay in the same city ';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _detectingCity = false;
        _citySupported = false;
        _serviceCity = null;
        _detectedCity = 'Unknown';
        _cityGateMessage =
            'Could not detect your city. Check GPS and try again.';
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
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
      // Backend already scopes to the signed-in user. Avoid dropping rows when
      // local phone was a Firebase UID or otherwise mismatched.
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

  String get _activeSenderPhone {
    final fromField = _sanitizePhone(_senderPhoneCtrl.text);
    if (fromField.isNotEmpty) return fromField;
    return _sanitizePhone(_senderPhone);
  }

  Future<void> _trackDelivery() async {
    final query = _trackCtrl.text.trim();
    if (query.isEmpty) {
      _toast('Enter your tracking number (e.g. VC506683).', isError: true);
      return;
    }
    setState(() => _tracking = true);
    try {
      final data = await _courierService.getMyDeliveryByTrackingOrId(
        query,
        senderPhone: _activeSenderPhone,
        senderEmail: _senderEmail.isEmpty ? null : _senderEmail,
      );
      if (!mounted) return;
      setState(() {
        _trackingResult = data;
        _trackedDeliveryId = data.courierId;
        if (data.trackingCode.isNotEmpty) {
          _trackCtrl.text = data.trackingCode;
        }
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
        final latest = await _courierService.getMyDeliveryById(
          _trackedDeliveryId!,
          senderPhone: _activeSenderPhone,
          senderEmail: _senderEmail.isEmpty ? null : _senderEmail,
        );
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
    if (!_citySupported || _serviceCity == null) {
      _toast(
        _cityGateMessage.isNotEmpty
            ? _cityGateMessage
            : 'Sorry, Vero Courier is not available in your city. We are expanding soon.',
        isError: true,
      );
      return;
    }
    if (!_sendingDetailsComplete || !_hasValidSendingDetails()) {
      _toast(
        'Complete sending details first, then tap Next.',
        isError: true,
      );
      setState(() {
        _selectedService = 0;
        _sendingStep = 0;
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final intraCityError = _validateIntraCityBooking();
    if (intraCityError != null) {
      _toast(intraCityError, isError: true);
      return;
    }

    final phone = _sanitizePhone(_senderPhoneCtrl.text);
    if (phone.isEmpty) {
      _toast('Enter a valid sender phone number (not an account ID).', isError: true);
      setState(() {
        _selectedService = 0;
        _sendingStep = 0;
      });
      return;
    }

    _senderName = _senderNameCtrl.text.trim();
    _senderPhone = phone;
    _senderCity = _serviceCityLabel;

    setState(() => _submitting = true);
    final senderUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final mergedAdditionalInfo = [
      _additionalCtrl.text.trim(),
      if (_senderNameCtrl.text.trim().isNotEmpty)
        'Sender: ${_senderNameCtrl.text.trim()}',
      if (senderUid.isNotEmpty) 'SenderUid: $senderUid',
      if (_recipientNameCtrl.text.trim().isNotEmpty)
        'Recipient: ${_recipientNameCtrl.text.trim()}',
      if (_sanitizePhone(_recipientPhoneCtrl.text).isNotEmpty)
        'Recipient Phone: ${_sanitizePhone(_recipientPhoneCtrl.text)}',
      if (_recipientAddressCtrl.text.trim().isNotEmpty)
        'Recipient Address: ${_recipientAddressCtrl.text.trim()}',
      'ServiceCity: $_senderCity',
      'IntraCityOnly: yes',
    ].where((e) => e.isNotEmpty).join(' | ');

    final email = _senderEmail.trim().isNotEmpty
        ? _senderEmail.trim()
        : (FirebaseAuth.instance.currentUser?.email?.trim().isNotEmpty == true
            ? FirebaseAuth.instance.currentUser!.email!.trim()
            : 'no-email@vero.local');

    try {
      await _persistSendingDraft(complete: true);
      final created = await _courierService.createDelivery(
        CreateCourierDeliveryDto(
          courierPhone: _senderPhone,
          courierEmail: email,
          courierCity: _senderCity,
          pickupLocation: _pickupCtrl.text.trim(),
          dropoffLocation: _dropoffCtrl.text.trim(),
          typeOfGoods: _selectedGoodsType,
          descriptionOfGoods: _descriptionCtrl.text.trim(),
          additionalInformation: mergedAdditionalInfo,
        ),
      );
      if (!mounted) return;
      final code = created.trackingCode.isNotEmpty
          ? created.trackingCode
          : '#${created.courierId}';
      _toast('Delivery created: $code');
      _formKey.currentState?.reset();
      _pickupCtrl.clear();
      _dropoffCtrl.clear();
      _selectedGoodsType = null;
      _descriptionCtrl.clear();
      _additionalCtrl.clear();
      // Keep sender + recipient for the next booking; they stay in prefs.
      _trackCtrl.text = code;
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

  Future<void> _advanceSendingStep() async {
    if (!_citySupported || _serviceCity == null) {
      _toast(
        _cityGateMessage.isNotEmpty
            ? _cityGateMessage
            : 'Sorry, Vero Courier is not available in your city. We are expanding soon.',
        isError: true,
      );
      return;
    }

    if (_sendingStep == 0) {
      final missing = <String>[];
      if (_senderNameCtrl.text.trim().isEmpty) missing.add('Sender full name');
      final phone = _sanitizePhone(_senderPhoneCtrl.text);
      if (phone.isEmpty) {
        missing.add('Valid sender phone number');
      } else {
        _senderPhoneCtrl.text = phone;
      }
      if (_senderAddressCtrl.text.trim().isEmpty) missing.add('Sender address');
      if (missing.isNotEmpty) {
        _toast('Complete sender details: ${missing.join(', ')}', isError: true);
        return;
      }

      final senderMismatch = _senderLocationMismatch();
      if (senderMismatch != null) {
        _toast(senderMismatch, isError: true);
        return;
      }

      setState(() {
        _sendingStep = 1;
        _senderCity = _serviceCityLabel;
      });
      await _persistSendingDraft(complete: false);
      return;
    }

    await _saveSendingDetails();
  }

  Future<void> _saveSendingDetails() async {
    if (!_citySupported || _serviceCity == null) {
      _toast(
        _cityGateMessage.isNotEmpty
            ? _cityGateMessage
            : 'Sorry, Vero Courier is not available in your city. We are expanding soon.',
        isError: true,
      );
      return;
    }
    final missing = <String>[];
    if (_senderNameCtrl.text.trim().isEmpty) missing.add('Sender full name');
    final phone = _sanitizePhone(_senderPhoneCtrl.text);
    if (phone.isEmpty) {
      missing.add('Valid sender phone number');
    } else {
      _senderPhoneCtrl.text = phone;
    }
    if (_senderAddressCtrl.text.trim().isEmpty) missing.add('Sender address');
    if (_recipientNameCtrl.text.trim().isEmpty) missing.add('Recipient full name');
    final recipientPhone = _sanitizePhone(_recipientPhoneCtrl.text);
    if (recipientPhone.isEmpty) {
      missing.add('Valid recipient phone number');
    } else {
      _recipientPhoneCtrl.text = recipientPhone;
    }
    if (_recipientAddressCtrl.text.trim().isEmpty) missing.add('Recipient address');
    if (missing.isNotEmpty) {
      _toast('Complete all fields first: ${missing.join(', ')}', isError: true);
      return;
    }

    final intraCityError = _validateIntraCityBooking();
    if (intraCityError != null) {
      _toast(intraCityError, isError: true);
      return;
    }

    setState(() {
      _senderName = _senderNameCtrl.text.trim();
      _senderPhone = phone;
      _senderCity = _serviceCityLabel;
      _sendingDetailsComplete = true;
      _sendingStep = 1;
      _syncParcelLocationsFromSendingDetails();
    });
    await _persistSendingDraft(complete: true);
    await _onServiceTabChanged(1);
  }

  Widget _deliveryCard(CourierDelivery d) {
    return CourierDeliveryCard(
      delivery: d,
      footer: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () async {
            _trackCtrl.text =
                d.trackingCode.isNotEmpty ? d.trackingCode : '${d.courierId}';
            if (_selectedService != 2) {
              await _onServiceTabChanged(2);
            }
            await _trackDelivery();
          },
          icon: const Icon(Icons.search, size: 16),
          label: const Text('Track'),
        ),
      ),
    );
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
    if (_checkingAuth) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: _veroOrange),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _pageBg,
      body: RefreshIndicator(
        onRefresh: _isLoggedIn ? _loadDeliveries : () async {},
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
          children: [
            _buildHeader(context),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _isLoggedIn
                  ? _buildLoggedInBody()
                  : _buildNotLoggedInBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(28),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF9A1F), Color(0xFFFF7A00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.of(context).padding.top + 14,
            16,
            20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 4),
                  Container(
                    height: 52,
                    width: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.local_shipping,
                      color: Colors.white,
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
              const SizedBox(height: 16),
              const Text(
                'City courier, made simple',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Book pickup, hand off securely, follow progress live.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotLoggedInBody() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFEAEAEA)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _veroOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.lock,
                color: _veroOrange,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Not logged in',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please log in to book courier deliveries and track your parcels.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _veroOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                  await _checkAuth();
                },
                child: const Text(
                  'Log in',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedInBody() {
    return Column(
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
                    child: Text(
                      'Detecting your city for courier availability...',
                    ),
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
                _cityGateMessage.isNotEmpty
                    ? _cityGateMessage
                    : (_citySupported
                        ? 'Vero Courier is available in $_detectedCity '
                            '(same-city only).'
                        : 'Sorry, Vero Courier is not available in your city. '
                            'We are expanding soon.'),
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
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    );
  }

  Widget _senderCard() {
    return _modernDetailCard(
      key: const ValueKey('senderCard'),
      accent: _skyBlue,
      icon: Icons.account_circle,
      title: 'From you',
      subtitle: 'Pickup in $_serviceCityLabel only ($_serviceCityCode)',
      child: Column(
        children: [
          _field(
            _senderNameCtrl,
            'Full Name',
            hint: 'Enter your full name',
          ),
          _field(
            _senderPhoneCtrl,
            'Phone Number',
            hint: 'e.g. 0999 123 456',
            keyboardType: TextInputType.phone,
          ),
          _field(
            _senderAddressCtrl,
            'Pickup address',
            hint: 'Street / area in $_serviceCityLabel',
          ),
        ],
      ),
    );
  }

  Widget _recipientCard() {
    return _modernDetailCard(
      key: const ValueKey('recipientCard'),
      accent: _mintGreen,
      icon: Icons.location_on,
      title: 'To recipient',
      subtitle:
          'Must be in $_serviceCityLabel ($_serviceCityCode → $_serviceCityCode)',
      child: Column(
        children: [
          _field(_recipientNameCtrl, 'Full Name', hint: 'Recipient name'),
          _field(
            _recipientPhoneCtrl,
            'Phone Number',
            hint: 'Recipient phone',
            keyboardType: TextInputType.phone,
          ),
          _field(
            _recipientAddressCtrl,
            'Delivery address',
            hint: 'Street / area in $_serviceCityLabel — not another city',
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _modernDetailCard({
    required Key key,
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      key: key,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: accent.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _sendingStepIndicator() {
    return Row(
      children: [
        _stepDot(active: _sendingStep == 0, done: _sendingStep > 0, label: 'Sender'),
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: _sendingStep > 0
                ? _mintGreen.withValues(alpha: 0.55)
                : const Color(0xFFE5E7EB),
          ),
        ),
        _stepDot(active: _sendingStep == 1, done: _sendingDetailsComplete, label: 'Recipient'),
      ],
    );
  }

  Widget _stepDot({
    required bool active,
    required bool done,
    required String label,
  }) {
    final color = done
        ? _mintGreen
        : (active ? _veroOrange : const Color(0xFF9CA3AF));
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          height: 28,
          width: 28,
          decoration: BoxDecoration(
            color: active || done ? color : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(
            done ? Icons.check_rounded : Icons.circle,
            size: done ? 16 : 8,
            color: active || done ? Colors.white : color,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _animatedSendingCard() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: Offset(_sendingStep == 0 ? -0.08 : 0.08, 0.04),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: _sendingStep == 0 ? _senderCard() : _recipientCard(),
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
          const SizedBox(height: 6),
          Text(
            'Same-city courier only in $_serviceCityLabel '
            '($_serviceCityCode → $_serviceCityCode). '
            'Not intercity.',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
          ),
          const SizedBox(height: 14),
          _sendingStepIndicator(),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _loadingSendingDetails
                ? const _DetailsLoadingCard()
                : _animatedSendingCard(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (_sendingStep > 0) ...[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => setState(() => _sendingStep = 0),
                    child: const Text(
                      'Back',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: _sendingStep > 0 ? 2 : 1,
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
                  onPressed: _advanceSendingStep,
                  icon: Icon(
                    _sendingStep == 0
                        ? Icons.arrow_forward
                        : Icons.check_circle,
                    size: 20,
                  ),
                  label: Text(
                    _sendingStep == 0 ? 'Continue' : 'Next: parcel details',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
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
                      _field(
                        _pickupCtrl,
                        'pickupLocation',
                        hint: 'Area in $_serviceCityLabel',
                      ),
                      _field(
                        _dropoffCtrl,
                        'dropoffLocation',
                        hint: 'Also in $_serviceCityLabel (same city)',
                      ),
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
                              : const Icon(Icons.send),
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
                    child: const Icon(Icons.search, color: _violet),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _trackCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Tracking number (e.g. VC506683)',
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
                    const Icon(Icons.history, color: _violet, size: 18),
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
      ('Sending Details', Icons.inventory_2, _skyBlue),
      ('Send a Parcel', Icons.local_shipping, _mintGreen),
      ('Progress', Icons.flight_takeoff, _violet),
      ('Shipping History', Icons.history, _rose),
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
                child: Opacity(
                  opacity: _canAccessServiceTab(i) ? 1 : 0.45,
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
            ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = true,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
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

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, ByteData;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/GernalServices/address_service.dart';
import 'package:vero360_app/GeneralModels/address_model.dart';

class ProfileQrPage extends StatefulWidget {
  const ProfileQrPage({
    super.key,
    this.name,
    this.email,
    this.phone,
    this.address,
    this.profilePictureUrl,
  });

  final String? name;
  final String? email;
  final String? phone;
  final String? address;
  final String? profilePictureUrl;

  @override
  State<ProfileQrPage> createState() => _ProfileQrPageState();
}

class _ProfileQrPageState extends State<ProfileQrPage> {
  final Color _brand = const Color(0xFFFF8A00);
  final GlobalKey _qrCompositeKey = GlobalKey();
  final AddressService _addressService = AddressService();

  /// vCard 3.0 customer card: name, address, email, phone (no photo).
  String _buildQrData([String? addressOverride]) {
    final name = widget.name ?? '';
    final email = widget.email ?? '';
    final phone = widget.phone ?? '';
    final address = addressOverride ?? _defaultAddressLine;
    if (name.isEmpty && email.isEmpty && phone.isEmpty && address.isEmpty) {
      return 'vero360://users/me';
    }
    return _buildVCard(name, email, phone, address);
  }

  static String _escapeVCard(String s) {
    return s.replaceAll(r'\', r'\\').replaceAll('\n', r'\n').replaceAll('\r', '');
  }

  static String _buildVCard(
      String name, String email, String phone, String address) {
    final sb = StringBuffer();
    sb.writeln('BEGIN:VCARD');
    sb.writeln('VERSION:3.0');
    if (name.isNotEmpty) sb.writeln('FN:${_escapeVCard(name)}');
    if (name.isNotEmpty) sb.writeln('N:$name;;;;');
    if (phone.isNotEmpty) sb.writeln('TEL:$phone');
    if (email.isNotEmpty) sb.writeln('EMAIL:$email');
    if (address.isNotEmpty) sb.writeln('ADR;TYPE=HOME:;;${_escapeVCard(address)};;;;');
    sb.writeln('ORG:Vero360');
    sb.writeln('END:VCARD');
    return sb.toString();
  }

  Uint8List? _qrPng;
  bool _saving = false;
  bool _building = true;
  String _qrData = 'vero360://users/me';
  String _defaultAddressLine = '';
  String _profilePictureUrl = '';
  String _displayName = '';
  String _displayEmail = '';
  String _displayPhone = '';

  @override
  void initState() {
    super.initState();
    _loadDataAndBuildQr();
  }

  @override
  void didUpdateWidget(ProfileQrPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name ||
        oldWidget.email != widget.email ||
        oldWidget.phone != widget.phone ||
        oldWidget.address != widget.address ||
        oldWidget.profilePictureUrl != widget.profilePictureUrl) {
      _profilePictureUrl = widget.profilePictureUrl ?? '';
      _loadDataAndBuildQr();
    }
  }

  /// Load default address from addresses/me (AddressService). Returns display line.
  Future<String> _loadDefaultAddress() async {
    try {
      final list = await _addressService.getMyAddresses();
      Address? defaultOrFirst;
      for (final a in list) {
        if (a.isDefault) {
          defaultOrFirst = a;
          break;
        }
      }
      defaultOrFirst ??= list.isNotEmpty ? list.first : null;
      final line = defaultOrFirst?.displayLine.trim() ?? '';
      if (mounted) setState(() => _defaultAddressLine = line);
      return line;
    } catch (_) {
      if (mounted) setState(() => _defaultAddressLine = '');
      return '';
    }
  }

  Future<void> _loadDataAndBuildQr() async {
    _profilePictureUrl = widget.profilePictureUrl ?? '';
    if (_profilePictureUrl.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      _profilePictureUrl = prefs.getString('profilepicture') ?? '';
    }

    final hasArgs = widget.name != null ||
        widget.email != null ||
        widget.phone != null ||
        widget.address != null;

    String addressLine = await _loadDefaultAddress();
    if (widget.address != null && widget.address!.trim().isNotEmpty) {
      addressLine = widget.address!.trim();
      if (mounted) setState(() => _defaultAddressLine = addressLine);
    }

    String displayName = widget.name ?? '';
    String displayEmail = widget.email ?? '';
    String displayPhone = widget.phone ?? '';

    if (hasArgs) {
      _qrData = _buildQrData(addressLine);
    } else {
      final prefs = await SharedPreferences.getInstance();
      displayName = prefs.getString('fullName') ?? prefs.getString('name') ?? '';
      displayEmail = prefs.getString('email') ?? '';
      displayPhone = prefs.getString('phone') ?? '';
      if (addressLine.isEmpty) {
        final a = prefs.getString('address') ?? '';
        if (a.trim().isNotEmpty) {
          addressLine = a.trim();
          if (mounted) setState(() => _defaultAddressLine = addressLine);
        }
      }
      _qrData = (displayName.isNotEmpty || displayEmail.isNotEmpty || displayPhone.isNotEmpty || addressLine.isNotEmpty)
          ? _buildVCard(displayName, displayEmail, displayPhone, addressLine)
          : 'vero360://users/me';
    }
    if (mounted) {
      setState(() {
        _displayName = displayName;
        _displayEmail = displayEmail;
        _displayPhone = displayPhone;
      });
    }
    if (mounted) _buildQrPng();
  }

  Widget _contactRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _brand),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF222222),
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _buildQrPng() async {
    try {
      setState(() => _building = true);
      final data = _qrData;

      // 1) Validate the data and build the QR code matrix (H = center can be covered by photo)
      final validation = QrValidator.validate(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
      );
      if (validation.status != QrValidationStatus.valid || validation.qrCode == null) {
        throw Exception('Invalid QR data');
      }

      // 2) Paint it to PNG bytes (hi-res so the saved image is crisp)
      final painter = QrPainter.withQr(
        qr: validation.qrCode!,
        color: const Color(0xFF000000),
        emptyColor: const Color(0xFFFFFFFF),
        gapless: true,
      );

      final ByteData? byteData = await painter.toImageData(
        1024, // pixels; higher => crisper saved image
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) throw Exception('Failed to render QR to PNG bytes');

      setState(() {
        _qrPng = byteData.buffer.asUint8List();
      });
    } catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Failed to generate QR',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  Future<bool> _ensureSavePermission() async {
    if (kIsWeb) return false;

    if (Platform.isAndroid) {
      final photos = await Permission.photos.request(); // Android 13+
      if (photos.isGranted) return true;

      final storage = await Permission.storage.request(); // Android 12-
      if (storage.isGranted) return true;

      return false;
    }

    if (Platform.isIOS) {
      var perm = await Permission.photosAddOnly.request();
      if (perm.isGranted) return true;
      perm = await Permission.photos.request();
      return perm.isGranted;
    }

    return false;
  }

  Future<void> _saveQrToGallery() async {
    if (kIsWeb) {
      ToastHelper.showCustomToast(
        context, 'Saving to gallery isn’t supported on web',
        isSuccess: false, errorMessage: 'Web platform',
      );
      return;
    }
    if (_qrPng == null || _qrPng!.isEmpty) {
      ToastHelper.showCustomToast(
        context, 'QR not ready yet',
        isSuccess: false, errorMessage: 'No bytes',
      );
      return;
    }

    try {
      setState(() => _saving = true);

      final allowed = await _ensureSavePermission();
      if (!allowed) {
        ToastHelper.showCustomToast(
          context, 'Permission required to save image',
          isSuccess: false, errorMessage: 'Photos/Storage permission not granted',
        );
        return;
      }

      Uint8List bytesToSave = _qrPng!;
      final boundary = _qrCompositeKey.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary) {
        try {
          final image = await boundary.toImage(pixelRatio: 3.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            bytesToSave = byteData.buffer.asUint8List();
          }
        } catch (_) {}
      }

      final fileName = 'vero360_profile_qr_${DateTime.now().millisecondsSinceEpoch}';
      final SaveResult result = await SaverGallery.saveImage(
        bytesToSave,
        quality: 100,
        extension: 'png',
        fileName: fileName,
        androidRelativePath: 'Pictures/Vero360/QR',
        skipIfExists: false,
      );

      if (result.isSuccess) {
        ToastHelper.showCustomToast(
          context, 'QR saved to gallery',
          isSuccess: true, errorMessage: '',
        );
      } else {
        ToastHelper.showCustomToast(
          context, 'Failed to save QR',
          isSuccess: false, errorMessage: result.errorMessage ?? 'Unknown error',
        );
      }
    } catch (e) {
      ToastHelper.showCustomToast(
        context, 'Error saving QR',
        isSuccess: false, errorMessage: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF222222),
        );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF222222),
        title: const Text('My Vero360 QR'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 22,
                  spreadRadius: -8,
                  offset: Offset(0, 14),
                  color: Color(0x1A000000),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_brand.withValues(alpha: .15), Colors.white],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.qr_code_2_rounded,
                      size: 40, color: Color(0xFF6B778C)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vero360 App', style: titleStyle),
                      const SizedBox(height: 6),
                      Text(
                        'Scan to add my Vero360 customer card (name, address, email, phone).',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: const Color(0xFF6B778C)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // QR Card (shows PNG we generated)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 22,
                  spreadRadius: -8,
                  offset: Offset(0, 14),
                  color: Color(0x1A000000),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'Vero360 — Customer card QR',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF222222),
                      ),
                ),
                const SizedBox(height: 12),
                 
                      
                    
                  
                RepaintBoundary(
                  key: _qrCompositeKey,
                  child: Container(
                    width: 240,
                    height: 240,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x11000000)),
                    ),
                    child: _building
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : (_qrPng == null
                            ? const Text('Failed to render QR')
                            : Stack(
                                alignment: Alignment.center,
                                clipBehavior: Clip.antiAlias,
                                children: [
                                  Image.memory(
                                    _qrPng!,
                                    width: 240,
                                    height: 240,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.high,
                                    gaplessPlayback: true,
                                  ),
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 4,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.12),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: _profilePictureUrl.isNotEmpty
                                          ? Image.network(
                                              _profilePictureUrl,
                                              fit: BoxFit.cover,
                                              width: 56,
                                              height: 56,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(
                                                      Icons.person,
                                                      size: 28,
                                                      color: Color(0xFF6B778C)),
                                            )
                                          : const Icon(
                                              Icons.person,
                                              size: 28,
                                              color: Color(0xFF6B778C),
                                            ),
                                    ),
                                  ),
                                ],
                              )),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Vero360 customer card — name, default address, email & phone.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF6B778C)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('Regenerate'),
                  onPressed: _building ? null : _buildQrPng,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save to gallery'),
                  onPressed: _saving || _building ? null : _saveQrToGallery,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

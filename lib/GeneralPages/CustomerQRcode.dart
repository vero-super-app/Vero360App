import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, ByteData;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:vero360_app/utils/toasthelper.dart';

class ProfileQrPage extends StatefulWidget {
  const ProfileQrPage({Key? key}) : super(key: key);

  @override
  State<ProfileQrPage> createState() => _ProfileQrPageState();
}

class _ProfileQrPageState extends State<ProfileQrPage> {
  final Color _brand = const Color(0xFFFF8A00);

  /// Put whatever you want to encode here.
  /// If you prefer deep links: 'vero360://users/me'
  static const String _qrData = 'vero360://users/me';

  Uint8List? _qrPng; // cached PNG bytes
  bool _saving = false;
  bool _building = true;

  @override
  void initState() {
    super.initState();
    _buildQrPng();
  }

  Future<void> _buildQrPng() async {
    try {
      setState(() => _building = true);

      // 1) Validate the data and build the QR code matrix
      final validation = QrValidator.validate(
        data: _qrData,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
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

      final ByteData? data = await painter.toImageData(
        1024, // pixels; higher => crisper saved image
        format: ui.ImageByteFormat.png,
      );
      if (data == null) throw Exception('Failed to render QR to PNG bytes');

      setState(() {
        _qrPng = data.buffer.asUint8List();
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

      final fileName = 'vero360_profile_qr_${DateTime.now().millisecondsSinceEpoch}';
      final SaveResult result = await SaverGallery.saveImage(
        _qrPng!,
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
                        'Scan to add me on VeroChat or view my profile.',
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
                  'Vero360 — Profile QR',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF222222),
                      ),
                ),
                const SizedBox(height: 12),
                Container(
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
                          width: 28, height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : (_qrPng == null
                          ? const Text('Failed to render QR')
                          : Image.memory(
                              _qrPng!,
                              width: 220,
                              height: 220,
                              filterQuality: FilterQuality.high,
                              gaplessPlayback: true,
                            )),
                ),
                const SizedBox(height: 10),
                Text(
                  'Scan with any QR app or the Vero360 app to view my profile.',
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

import 'package:universal_io/io.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/features/DigitalServices/digital_product.dart';

const Color _veroOrange = Color(0xFFFF8A00);
const Color _ink = Color(0xFF1A1109);

class DigitalPayoutKycPayload {
  const DigitalPayoutKycPayload({
    required this.kind,
    this.alipayWechatCodeUrl = '',
    this.idInHandUrl = '',
    this.faceUrl = '',
    this.binanceId = '',
    this.binanceAddress = '',
    this.binanceCodeUrl = '',
  });

  final DigitalPayoutKycKind kind;
  final String alipayWechatCodeUrl;
  final String idInHandUrl;
  final String faceUrl;
  final String binanceId;
  final String binanceAddress;
  final String binanceCodeUrl;

  Map<String, dynamic> toMap() => {
        'kind': kind == DigitalPayoutKycKind.cny ? 'cny' : 'usdt',
        'alipayWechatCodeUrl': alipayWechatCodeUrl,
        'idInHandUrl': idInHandUrl,
        'faceUrl': faceUrl,
        'binanceId': binanceId,
        'binanceAddress': binanceAddress,
        'binanceCodeUrl': binanceCodeUrl,
      };
}

/// Collects Alipay/WeChat + ID/face (CNY) or Binance ID/address (USDT).
class DigitalPayoutKycSection extends StatefulWidget {
  const DigitalPayoutKycSection({
    super.key,
    required this.product,
  });

  final DigitalProduct product;

  @override
  State<DigitalPayoutKycSection> createState() => DigitalPayoutKycSectionState();
}

class DigitalPayoutKycSectionState extends State<DigitalPayoutKycSection> {
  final _picker = ImagePicker();
  final _binanceIdCtrl = TextEditingController();
  final _binanceAddressCtrl = TextEditingController();

  XFile? _codeFile;
  XFile? _idFile;
  XFile? _faceFile;
  XFile? _binanceCodeFile;
  String? _error;

  DigitalPayoutKycKind? get _kind => widget.product.payoutKycKind;

  @override
  void dispose() {
    _binanceIdCtrl.dispose();
    _binanceAddressCtrl.dispose();
    super.dispose();
  }

  Future<DigitalPayoutKycPayload?> validateAndUpload() async {
    final kind = _kind;
    if (kind == null) return null;

    if (kind == DigitalPayoutKycKind.cny) {
      if (_codeFile == null || _idFile == null || _faceFile == null) {
        setState(() {
          _error =
              'Upload your Alipay or WeChat code, a photo of your ID held in your hands, and a photo of your face.';
        });
        return null;
      }
    } else {
      final id = _binanceIdCtrl.text.trim();
      final addr = _binanceAddressCtrl.text.trim();
      if (id.isEmpty && addr.isEmpty && _binanceCodeFile == null) {
        setState(() {
          _error =
              'Enter your Binance ID or wallet address, or upload your Binance code.';
        });
        return null;
      }
    }

    setState(() => _error = null);

    var user = FirebaseAuth.instance.currentUser;
    user ??= (await FirebaseAuth.instance.signInAnonymously()).user;
    if (user == null) {
      setState(() => _error = 'Could not start a secure upload session.');
      return null;
    }

    Future<String> put(XFile file, String slot) async {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final path = 'profile_photos/${user!.uid}_digitalkyc_${slot}_$stamp.jpg';
      final ref = FirebaseStorage.instance.ref(path);
      final meta = SettableMetadata(contentType: 'image/jpeg');
      if (!kIsWeb && file.path.isNotEmpty) {
        await ref.putFile(File(file.path), meta);
      } else {
        await ref.putData(await file.readAsBytes(), meta);
      }
      return ref.getDownloadURL();
    }

    if (kind == DigitalPayoutKycKind.cny) {
      final codeUrl = await put(_codeFile!, 'alipay');
      final idUrl = await put(_idFile!, 'idhand');
      final faceUrl = await put(_faceFile!, 'face');
      return DigitalPayoutKycPayload(
        kind: kind,
        alipayWechatCodeUrl: codeUrl,
        idInHandUrl: idUrl,
        faceUrl: faceUrl,
      );
    }

    final codeUrl = _binanceCodeFile == null
        ? ''
        : await put(_binanceCodeFile!, 'binance');
    return DigitalPayoutKycPayload(
      kind: kind,
      binanceId: _binanceIdCtrl.text.trim(),
      binanceAddress: _binanceAddressCtrl.text.trim(),
      binanceCodeUrl: codeUrl,
    );
  }

  Future<void> _pick({
    required void Function(XFile file) onPicked,
    required bool cameraOnly,
  }) async {
    ImageSource? source = ImageSource.camera;
    if (!cameraOnly) {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded, color: _veroOrange),
                title: const Text('Take photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: _veroOrange),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;
    }
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 72,
      maxWidth: 1600,
    );
    if (file == null) return;
    setState(() {
      onPicked(file);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    if (kind == null) return const SizedBox.shrink();

    final isCny = kind == DigitalPayoutKycKind.cny;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE0B8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payout details',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isCny
                ? 'For Chinese Yuan / USD TT we send to your Alipay or WeChat. Upload the code, hold your ID in your hands, and take a photo of your face.'
                : 'For USDT we send to your Binance account. Enter your Binance ID or wallet address, and optionally upload your code.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          if (isCny) ...[
            _photoTile(
              label: 'Alipay / WeChat code',
              hint: 'QR or payment code',
              file: _codeFile,
              cameraOnly: false,
              onPick: (f) => _codeFile = f,
            ),
            const SizedBox(height: 10),
            _photoTile(
              label: 'ID held in your hands',
              hint: 'National ID visible in both hands',
              file: _idFile,
              cameraOnly: true,
              onPick: (f) => _idFile = f,
            ),
            const SizedBox(height: 10),
            _photoTile(
              label: 'Your face',
              hint: 'Clear selfie showing your face',
              file: _faceFile,
              cameraOnly: true,
              onPick: (f) => _faceFile = f,
            ),
          ] else ...[
            _textField(
              controller: _binanceIdCtrl,
              label: 'Binance ID',
              hint: 'Your Binance user ID',
            ),
            const SizedBox(height: 10),
            _textField(
              controller: _binanceAddressCtrl,
              label: 'USDT address',
              hint: 'TRC20 / BEP20 wallet address',
            ),
            const SizedBox(height: 10),
            _photoTile(
              label: 'Binance code (optional)',
              hint: 'QR or screenshot of your Binance ID',
              file: _binanceCodeFile,
              cameraOnly: false,
              onPick: (f) => _binanceCodeFile = f,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFFFE0B8)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: _ink,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: const BorderSide(color: _veroOrange),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _photoTile({
    required String label,
    required String hint,
    required XFile? file,
    required bool cameraOnly,
    required void Function(XFile file) onPick,
  }) {
    return InkWell(
      onTap: () => _pick(onPicked: onPick, cameraOnly: cameraOnly),
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: file == null ? const Color(0xFFE5E7EB) : _veroOrange,
          ),
          color: const Color(0xFFFFFBF6),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFE0B8)),
              ),
              clipBehavior: Clip.antiAlias,
              child: file == null
                  ? Icon(
                      cameraOnly
                          ? Icons.photo_camera_rounded
                          : Icons.add_photo_alternate_outlined,
                      color: _veroOrange,
                    )
                  : kIsWeb
                      ? const Icon(Icons.check_circle, color: _veroOrange)
                      : Image.file(File(file.path), fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    file == null ? hint : 'Photo attached Â· tap to replace',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              file == null ? Icons.chevron_right_rounded : Icons.check_circle,
              color: file == null ? Colors.grey : _veroOrange,
            ),
          ],
        ),
      ),
    );
  }
}

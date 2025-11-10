// lib/Pages/profile_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// ✅ needed to set correct MIME on uploads
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:vero360_app/Pages/PostMarketplace.dart';
import 'package:vero360_app/Pages/PostlatestArrival.dart';
import 'package:vero360_app/Pages/Postpromotion.dart';
import 'package:vero360_app/Pages/myshop.dart';

import 'package:vero360_app/services/api_config.dart';

import 'package:vero360_app/Pages/Home/myorders.dart';
import 'package:vero360_app/Pages/QRcode.dart';
import 'package:vero360_app/Pages/ToRefund.dart';
import 'package:vero360_app/Pages/myaccomodation.dart';
import 'package:vero360_app/Pages/Toreceive.dart';
import 'package:vero360_app/Pages/Toship.dart';
import 'package:vero360_app/Pages/address.dart';
import 'package:vero360_app/Pages/changepassword.dart';
import 'package:vero360_app/models/Latest_model.dart';
import 'package:vero360_app/screens/login_screen.dart';
import 'package:vero360_app/services/auth_service.dart';
import 'package:vero360_app/services/latest_Services.dart';
import 'package:vero360_app/toasthelper.dart';
import 'package:vero360_app/Pages/MerchantApplicationForm.dart';

class MerchantProfilePage extends StatefulWidget {
  const MerchantProfilePage({Key? key}) : super(key: key);

  @override
  State<MerchantProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<MerchantProfilePage> {
  final Color _brandNavy = const Color(0xFF16284C);
  final Color _cardBg = Colors.white;
  final Color _chipGrey = const Color(0xFFF4F5F7);

  String name = "Guest User";
  String email = "No Email";
  String phone = "No Phone";
  String address = "No Address";
  String profileUrl = "";

  bool _loading = false;
  bool _offline = false; // show graceful banner if users/me fails (DNS/offline)

  String applicationStatus = ""; // approved | pending | under_review | rejected | submitted | ''
  String kycStatus = "";         // complete | incomplete | pending | unverified | ''
  bool isVerified = false;       // from API (isVerified / merchantVerified)
  bool reviewPending = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchCurrentUser();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      name       = prefs.getString('fullName') ?? prefs.getString('name') ?? 'Guest User';
      email      = prefs.getString('email') ?? 'No Email';
      phone      = prefs.getString('phone') ?? 'No Phone';
      address    = prefs.getString('address') ?? 'No Address';
      profileUrl = prefs.getString('profilepicture') ?? '';
      applicationStatus = (prefs.getString('applicationStatus') ?? '').toLowerCase();
      kycStatus        = (prefs.getString('kycStatus') ?? '').toLowerCase();
      isVerified       = prefs.getBool('merchant_verified') ?? false;
      reviewPending    = prefs.getBool('merchant_review_pending') ?? false;
    });
  }

  String _joinName(String? first, String? last, {required String fallback}) {
    final parts = [first, last].where((s) => s != null && s!.trim().isNotEmpty);
    if (parts.isEmpty) return fallback;
    return parts.join(' ');
  }

  Future<String> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ??
        prefs.getString('token') ??
        prefs.getString('authToken') ??
        '';
  }

bool _isUnderReviewStatus(String app, String kyc, bool verified) {
  if (verified) return false;
  final a = (app   ).trim().toLowerCase();
  final k = (kyc   ).trim().toLowerCase();

  const underReview = {
    'submitted', 'pending', 'under_review', 'in_review', 'awaiting_review'
  };

  // Under review if either applicationStatus OR kycStatus is in those states
  return underReview.contains(a) || underReview.contains(k) || k == 'pending';
}

Future<void> _optimisticallyMarkUnderReview() async {
  // Flip UI immediately after form submit
  setState(() {
    applicationStatus = 'submitted';
    kycStatus = 'pending';
    reviewPending = true;
  });
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('applicationStatus', 'submitted');
  await prefs.setString('kycStatus', 'pending');
  await prefs.setBool('merchant_review_pending', true);
}

Future<void> _persistUserToPrefs(Map<String, dynamic> data) async {
  final prefs = await SharedPreferences.getInstance();
  final user = (data['user'] is Map) ? (data['user'] as Map) : data;

  String _join(String? a, String? b) {
    final parts = [a, b].where((x) => x != null && x!.trim().isNotEmpty).map((x) => x!.trim()).toList();
    return parts.isEmpty ? '' : parts.join(' ');
  }

  final userName = (user['name'] ?? _join(user['firstName'], user['lastName'])).toString();
  final emailVal = (user['email'] ?? user['userEmail'] ?? '').toString();
  final phoneVal = (user['phone'] ?? '').toString();
  final picVal   = (user['profilepicture'] ?? user['profilePicture'] ?? '').toString();

  String addr = 'No Address';
  final addresses = user['addresses'];
  if (addresses is List && addresses.isNotEmpty) {
    final first = addresses.first;
    if (first is Map && first['address'] != null) addr = first['address'].toString();
    else if (first is String && first.trim().isNotEmpty) addr = first;
  } else if (user['address'] != null) {
    addr = user['address'].toString();
  }

  final serverAppStatus = (user['applicationStatus'] ?? user['merchantApplicationStatus'] ?? '').toString().toLowerCase();
  final serverKycStatus = (user['kycStatus'] ?? '').toString().toLowerCase();
  final serverIsVerified = (user['isVerified'] == true) || (user['merchantVerified'] == true) || (user['verified'] == true);

  setState(() {
    name       = (userName.trim().isEmpty) ? 'Guest User' : userName.trim();
    email      = (emailVal.trim().isEmpty) ? 'No Email' : emailVal.trim();
    phone      = (phoneVal.trim().isEmpty) ? 'No Phone' : phoneVal.trim();
    address    = (addr.trim().isEmpty) ? 'No Address' : addr.trim();
    profileUrl = picVal;

    if (serverAppStatus.isNotEmpty) applicationStatus = serverAppStatus;
    if (serverKycStatus.isNotEmpty) kycStatus = serverKycStatus;
    isVerified = serverIsVerified;

    // 🔁 ⬇️ replace your old reviewPending line with this:
    reviewPending = _isUnderReviewStatus(applicationStatus, kycStatus, isVerified);
  });

  await prefs.setString('fullName', name);
  await prefs.setString('name', name);
  await prefs.setString('email', email);
  await prefs.setString('phone', phone);
  await prefs.setString('address', address);
  await prefs.setString('profilepicture', profileUrl);
  await prefs.setString('applicationStatus', applicationStatus);
  await prefs.setString('kycStatus', kycStatus);
  await prefs.setBool('merchant_verified', isVerified);
  await prefs.setBool('merchant_review_pending', reviewPending);
}

  Future<void> _fetchCurrentUser() async {
    setState(() { _loading = true; _offline = false; });
    try {
      final token = await _getAuthToken();
      if (token.isEmpty) { setState(() => _loading = false); return; }

      final base = await ApiConfig.readBase();
      final response = await http.get(
        Uri.parse('$base/users/me'),
        headers: {'Authorization': 'Bearer $token','Accept': 'application/json'},
      );
      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final Map<String, dynamic> payload =
            decoded is Map && decoded['data'] is Map
                ? Map<String, dynamic>.from(decoded['data'])
                : (decoded is Map ? Map<String, dynamic>.from(decoded) : {});
        await _persistUserToPrefs(payload);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session expired. Please log in.')),
        );
      }
    } catch (e) {
      setState(() => _offline = true);
      debugPrint('Error fetching user: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPhotoSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () { Navigator.pop(context); _pickAndUpload(ImageSource.camera); },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () { Navigator.pop(context); _pickAndUpload(ImageSource.gallery); },
          ),
          if (profileUrl.isNotEmpty)
            ListTile(
  leading: const Icon(Icons.remove_circle_outline),
  title: const Text('Remove current photo'),
  onTap: () async {
    Navigator.pop(context);
    await _deleteProfilePicture(); // ← calls backend & clears local
  },
),

        ]),
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, maxWidth: 1400, imageQuality: 85);
      if (file == null) return;
      await _uploadProfilePicture(file);
    } catch (_) {
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Could not pick image', isSuccess: false, errorMessage: '');
    }
  }

  // ===== Helpers for upload =====
  String _safeFileName(XFile picked) {
    try {
      // image_picker exposes .name on most platforms
      // ignore: invalid_use_of_visible_for_testing_member
      final n = picked.name;
      if (n.trim().isNotEmpty) return n;
    } catch (_) {}
    final fromPath = picked.path.split('/').last;
    if (fromPath.trim().isNotEmpty) return fromPath;
    return 'profile.jpg';
  }

  Future<http.MultipartFile> _buildMultipartImage(String field, XFile picked) async {
    String filename = _safeFileName(picked);
    if (!filename.contains('.')) filename = '$filename.jpg';

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      // detect mime from header bytes + filename fallback
      final mimeStr = lookupMimeType(filename, headerBytes: bytes.take(12).toList()) ?? 'image/jpeg';
      final mediaType = MediaType.parse(mimeStr);
      return http.MultipartFile.fromBytes(field, bytes, filename: filename, contentType: mediaType);
    } else {
      final mimeStr = lookupMimeType(picked.path) ?? 'image/jpeg';
      final mediaType = MediaType.parse(mimeStr);
      return await http.MultipartFile.fromPath(field, picked.path, filename: filename, contentType: mediaType);
    }
  }

  Future<void> _uploadProfilePicture(XFile picked) async {
    final token = await _getAuthToken();
    if (token.isEmpty) {
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Please log in to update your photo', isSuccess: false, errorMessage: '');
      return;
    }

    setState(() => _loading = true);
    final base = await ApiConfig.readBase();

    Future<String?> _tryDirectUserUpload() async {
      final uri = Uri.parse('$base/users/me/profile-picture');
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token';

      // ✅ ensure proper contentType
      req.files.add(await _buildMultipartImage('file', picked));

      final sent = await req.send();
      final resp = await http.Response.fromStream(sent);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = jsonDecode(resp.body);
        final data = (body is Map && body['data'] is Map) ? body['data'] as Map : (body as Map? ?? {});
        return (data['profilepicture'] ?? data['profilePicture'] ?? data['url'])?.toString();
      }
      if (resp.statusCode == 404) return null; // endpoint not available → fallback
      throw Exception('Upload failed (${resp.statusCode}) ${resp.body}');
    }

    Future<String> _uploadGetUrlThenPutUser() async {
      // 1) upload to generic /upload to get URL
      final upReq = http.MultipartRequest('POST', Uri.parse('$base/upload'))
        ..headers['Authorization'] = 'Bearer $token';
      upReq.files.add(await _buildMultipartImage('file', picked));
      final upSent = await upReq.send();
      final upResp = await http.Response.fromStream(upSent);
      if (upResp.statusCode < 200 || upResp.statusCode >= 300) {
        throw Exception('Upload URL failed (${upResp.statusCode}) ${upResp.body}');
      }
      final upBody = jsonDecode(upResp.body);
      final url = (upBody is Map ? (upBody['url'] ?? upBody['data']?['url']) : null)?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Missing url from /upload');
      }

      // 2) update current user with URL
      final put = await http.put(
        Uri.parse('$base/users/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'profilepicture': url}),
      );
      if (put.statusCode < 200 || put.statusCode >= 300) {
        throw Exception('PUT /users/me failed (${put.statusCode}) ${put.body}');
      }
      return url;
    }

    try {
      String? url = await _tryDirectUserUpload();   // prefer single endpoint
      url ??= await _uploadGetUrlThenPutUser();     // fallback flow

      setState(() => profileUrl = url!);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', url);

      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Profile picture updated', isSuccess: true, errorMessage: '');
    } catch (e) {
      debugPrint('Upload error: $e');
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Failed to upload', isSuccess: false, errorMessage: e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteProfilePicture() async {
  final token = await _getAuthToken();
  if (token.isEmpty) {
    if (!mounted) return;
    ToastHelper.showCustomToast(context, 'Please log in first', isSuccess: false, errorMessage: '');
    return;
  }
  try {
    setState(() => _loading = true);
    final base = await ApiConfig.readBase();
    final resp = await http.delete(
      Uri.parse('$base/users/me/profile-picture'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      setState(() => profileUrl = '');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', '');
      ToastHelper.showCustomToast(context, 'Profile picture removed', isSuccess: true, errorMessage: '');
    } else {
      ToastHelper.showCustomToast(context, 'Failed to remove', isSuccess: false, errorMessage: resp.body);
    }
  } catch (e) {
    ToastHelper.showCustomToast(context, 'Failed to remove', isSuccess: false, errorMessage: e.toString());
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}


  Future<void> _logout() async {
    setState(() => _loading = true);
    try {
      await AuthService().logout(context: context);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fullName');
      await prefs.remove('name');
      await prefs.remove('email');
      await prefs.remove('phone');
      await prefs.remove('address');
      await prefs.remove('profilepicture');
    } catch (e) {
      debugPrint('Logout error: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: _brandNavy,
      elevation: 0,
      titleSpacing: 0,
      title: const Text('Merchant Profile', style: TextStyle(color: Colors.white)),
      actions: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
          ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: _logout,
          tooltip: 'Logout',
        ),
      ],
    );
  }

  Widget _offlineBanner() {
    if (!_offline) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEDEE),
        border: Border.all(color: const Color(0xFFFFC9CD)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: const [
          Icon(Icons.wifi_off_rounded, color: Colors.red),
          SizedBox(width: 8),
          Expanded(child: Text('You are offline or the server is unreachable. Showing cached info.', style: TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _reviewBanner() {
  // Hide entirely if verified/approved
  if (isVerified || applicationStatus == 'approved') return const SizedBox.shrink();

  final bool underReview = _isUnderReviewStatus(applicationStatus, kycStatus, isVerified);

  final String message = underReview
      ? 'Your application is under review'
      : 'start your KYC to become a verified merchant';

  final Widget cta = underReview
      ? const SizedBox.shrink()
      : TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MerchantApplicationForm(
                  onFinished: () async {
                    if (!mounted) return;
                    // ✅ switch UI immediately, then refresh from server
                    await _optimisticallyMarkUnderReview();
                    ToastHelper.showCustomToast(
                      context,
                      'Application submitted',
                      isSuccess: true,
                      errorMessage: '',
                    );
                    await _fetchCurrentUser();
                    Navigator.of(context).pop();
                  },
                ),
              ),
            );
          },
          child: const Text('Start KYC'),
        );

  return Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E5),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFFFD9B3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: Color(0xFFB86E00)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!underReview) const SizedBox(width: 8),
        cta,
      ],
    ),
  );
}

  

  // --- Header card: safe layout (no negative heights, no short Stack) ---
  Widget _topProfileCard() {
    final avatar = GestureDetector(
      onTap: _showPhotoSheet,
      child: CircleAvatar(
        radius: 26,
        backgroundColor: Colors.black12,
        backgroundImage: profileUrl.isNotEmpty ? NetworkImage(profileUrl) : null,
        child: profileUrl.isEmpty
            ? const Icon(Icons.person, size: 28, color: Colors.black45)
            : const SizedBox.shrink(),
      ),
    );

    final bool approved = isVerified || applicationStatus == 'approved';
    final Color chipBg  = approved ? const Color(0xFFE7F6EC) : const Color(0xFFFFF3E5);
    final Color chipFg  = approved ? Colors.green.shade700 : const Color.fromARGB(255, 235, 52, 1);
    final String chipText = approved
        ? 'APPROVED'
        : (applicationStatus.isEmpty ? 'UNVERIFIED MERCHANT' : applicationStatus.toUpperCase());

    final statusChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        chipText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: chipFg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );

    return Column(
      children: [
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: _brandNavy,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -40),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(phone, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                      const SizedBox(height: 6),
                      Row(children: [Flexible(child: statusChip)]),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints.tightFor(width: 36),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: PopupMenuButton<String>(
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(
                          value: 'active',
                          enabled: false,
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 16),
                              SizedBox(width: 8),
                              Text('Status'),
                            ],
                          ),
                        ),
                      ],
                      icon: const Icon(Icons.more_horiz),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // --- Quick actions (no overflow) ---
  Widget _ordersQuickActions() {
    final items = <_QuickAction>[
      _QuickAction('My Orders', Icons.book, () => _openBottomSheet(const OrdersPage())),
      _QuickAction('Shipped', Icons.local_shipping_outlined, () => _openBottomSheet(const ToShipPage())),
      _QuickAction('Received', Icons.move_to_inbox_outlined, () => _openBottomSheet(const DeliveredOrdersPage())),
      _QuickAction('Accomodation', Icons.house, () => _openBottomSheet(const MyBookingsPage())),
      _QuickAction('Refund', Icons.replay_circle_filled_outlined, () => _openBottomSheet(const ToRefundPage())),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final maxW = c.maxWidth;
          const spacing = 10.0;
          final targetTileWidth = 110.0;
          int perRow = math.max(2, (maxW / targetTileWidth).floor());
          perRow = perRow.clamp(2, 5);
          final tileW = (maxW - spacing * (perRow - 1)) / perRow;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            alignment: WrapAlignment.start,
            children: items
                .map((it) => SizedBox(width: tileW, child: _orderAction(it.label, it.icon, it.onTap)))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _orderAction(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _chipGrey, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: _brandNavy),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  void _openBottomSheet(Widget child) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(height: MediaQuery.of(context).size.height * 0.88, child: child),
    );
  }

  Widget _otherDetailsGrid() {
    final items = <_DetailItem>[
           _DetailItem('My Shop', Icons.shopping_bag_rounded, () { _openBottomSheet(const ServiceProviderCrudPage()); }),
    _DetailItem('Marketplace', Icons.storefront, () {
  _openBottomSheet(const MarketplaceCrudPage());
}),
_DetailItem('Promotions', Icons.local_offer, () {
  _openBottomSheet(const PromotionsCrudPage());
}),
_DetailItem('Latest Arrivals', Icons.rocket_launch, () {
  _openBottomSheet(const LatestArrivalsCrudPage());
}),


         _DetailItem('My Address', Icons.location_on, () { _openBottomSheet(const AddressPage()); }),
       _DetailItem('My transactions', Icons.history, _logout),


    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 8, 6, 10),
            child: Text('My Products', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          GridView.builder(
            itemCount: items.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisExtent: 100,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemBuilder: (_, i) => _detailTile(items[i]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom + 24;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: _appBar(),
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: bottomPad),
          child: Column(
            children: [
              _topProfileCard(),
              _offlineBanner(),
              const SizedBox(height: 12),
              _reviewBanner(),
              const SizedBox(height: 24),
              _ordersQuickActions(),
              _otherDetailsGrid(),
              const LatestArrivalsSection(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailTile(_DetailItem item) {
    return InkWell(
      onTap: () async { await item.onTap(); },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(color: _chipGrey, borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: _brandNavy, size: 24),
            const SizedBox(height: 8),
            Text(item.label, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _DetailItem {
  final String label;
  final IconData icon;
  final Future<void> Function() onTap;
  _DetailItem(this.label, this.icon, FutureOr<void> Function() handler)
      : onTap = (() { final result = handler(); return result is Future ? result : Future.value(); });
}

class _QuickAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  _QuickAction(this.label, this.icon, this.onTap);
}

// ===== Latest Arrivals (unchanged) =====
class LatestArrivalsSection extends StatefulWidget {
  const LatestArrivalsSection({super.key});
  @override
  State<LatestArrivalsSection> createState() => _LatestArrivalsSectionState();
}

class _LatestArrivalsSectionState extends State<LatestArrivalsSection> {
  final _service = LatestArrivalServices();
  late Future<List<LatestArrivalModels>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchLatestArrivals();
  }

  String _fmtKwacha(int n) {
    final s = n.toString();
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Latest Arrivals", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          FutureBuilder<List<LatestArrivalModels>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('Could not load arrivals.\n${snap.error}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                  ),
                );
              }
              final items = snap.data ?? const [];
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No items yet.', style: TextStyle(color: Colors.red))),
                );
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.78,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final it = items[i];
                  return _ProductCardFromApi(
                    imageUrl: it.imageUrl,
                    name: it.name,
                    priceText: 'MWK ${_fmtKwacha(it.price)}',
                    brandOrange: const Color(0xFFFF8A00),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ProductCardFromApi extends StatelessWidget {
  final String imageUrl;
  final String name;
  final String priceText;
  final Color brandOrange;

  const _ProductCardFromApi({
    required this.imageUrl,
    required this.name,
    required this.priceText,
    required this.brandOrange,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            child: imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 140, color: const Color(0xFFEDEDED),
                      child: const Center(child: Icon(Icons.image_not_supported_rounded)),
                    ),
                  )
                : Container(
                    height: 140, color: const Color(0xFFEDEDED),
                    child: const Center(child: Icon(Icons.image_not_supported_rounded)),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(priceText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.green)),
                  ]),
                ),
                IconButton(
                  onPressed: () => _showCardOptions(context, name),
                  icon: Icon(Icons.add_circle, color: brandOrange),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCardOptions(BuildContext context, String name) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Choose an action', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.shopping_cart, color: Colors.green),
            title: const Text('Add to cart'),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name added to cart')));
            },
          ),
          const Divider(height: 0),
          ListTile(
            leading: Icon(Icons.info_outline_rounded, color: brandOrange),
            title: const Text('More details'),
            onTap: () { Navigator.pop(context); },
          ),
        ]),
      ),
    );
  }
}

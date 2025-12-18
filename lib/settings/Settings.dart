// lib/Pages/settings_page.dart
//
// Modern Settings page (NO KYC).
// Includes: Edit Profile, Change Password, My Address, Logout, Delete Account,
// App Version, Privacy Policy/Terms.
// Pulls cached user data from SharedPreferences + refreshes from API (/users/me)
// + uses Firebase Auth + Firebase Storage for profile photo.
//
// Add deps if missing in pubspec.yaml:
//   shared_preferences: ^2.2.3
//   http: ^1.2.2
//   firebase_auth: ^5.3.3
//   cloud_firestore: ^5.5.0
//   firebase_storage: ^12.3.7
//   image_picker: ^1.1.2
//   mime: ^1.0.6
//   package_info_plus: ^8.0.2
//   url_launcher: ^6.3.0
//
// If your project already has a SettingsPage in address.dart, you can copy this there
// BUT avoid importing address.dart inside itself.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/services/api_config.dart';
import 'package:vero360_app/toasthelper.dart';
import 'package:vero360_app/screens/login_screen.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required void Function() onBackToHomeTab});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _picker = ImagePicker();

  bool _loading = true;
  bool _refreshing = false;
  bool _offline = false;

  // Cached user profile
  String _uid = '';
  String _name = 'Guest User';
  String _email = 'No Email';
  String _phone = 'No Phone';
  String _address = 'No Address';
  String _photoUrl = '';

  // App info
  String _appVersion = '—';
  String _buildNumber = '—';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadAppInfo();
    await _loadCachedProfile();
    await _hydrateFromFirebaseAuth();
    await _fetchUserMeFromApi(); // best effort
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
      _buildNumber = info.buildNumber;
    } catch (_) {
      // ignore (dependency missing or platform issue)
    }
  }

  Future<void> _loadCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('fullName') ?? prefs.getString('name') ?? _name;
      _email = prefs.getString('email') ?? _email;
      _phone = prefs.getString('phone') ?? _phone;
      _address = prefs.getString('address') ?? _address;
      _photoUrl = prefs.getString('profilepicture') ?? '';
    });
  }

  Future<void> _hydrateFromFirebaseAuth() async {
    final u = _auth.currentUser;
    if (u == null) return;

    _uid = u.uid;
    if ((u.displayName ?? '').trim().isNotEmpty) _name = u.displayName!.trim();
    if ((u.email ?? '').trim().isNotEmpty) _email = u.email!.trim();
    if ((u.photoURL ?? '').trim().isNotEmpty) _photoUrl = u.photoURL!.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uid', _uid);
    await prefs.setString('email', _email);
    if (_name.isNotEmpty) {
      await prefs.setString('fullName', _name);
      await prefs.setString('name', _name);
    }
    if (_photoUrl.isNotEmpty) await prefs.setString('profilepicture', _photoUrl);

    if (mounted) setState(() {});
  }

  Future<String> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ??
        prefs.getString('token') ??
        prefs.getString('authToken') ??
        '';
  }

  Future<void> _persistUserToPrefsFromApi(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final user = (data['user'] is Map) ? Map<String, dynamic>.from(data['user']) : data;

    final name = (user['name'] ??
            _joinName(user['firstName']?.toString(), user['lastName']?.toString(), fallback: 'Guest User'))
        .toString()
        .trim();

    final email = (user['email'] ?? user['userEmail'] ?? '').toString().trim();
    final phone = (user['phone'] ?? '').toString().trim();
    final pic = (user['profilepicture'] ?? user['profilePicture'] ?? user['photoURL'] ?? '').toString().trim();

    String addr = 'No Address';
    final addresses = user['addresses'];
    if (addresses is List && addresses.isNotEmpty) {
      final first = addresses.first;
      if (first is Map && first['address'] != null) addr = first['address'].toString();
      else if (first is String && first.trim().isNotEmpty) addr = first;
    } else if (user['address'] != null) {
      addr = user['address'].toString();
    }

    _name = name.isEmpty ? _name : name;
    _email = email.isEmpty ? _email : email;
    _phone = phone.isEmpty ? _phone : phone;
    _address = addr.trim().isEmpty ? _address : addr.trim();
    if (pic.isNotEmpty) _photoUrl = pic;

    await prefs.setString('fullName', _name);
    await prefs.setString('name', _name);
    await prefs.setString('email', _email);
    await prefs.setString('phone', _phone);
    await prefs.setString('address', _address);
    await prefs.setString('profilepicture', _photoUrl);

    if (mounted) setState(() {});
  }

  String _joinName(String? first, String? last, {required String fallback}) {
    final parts = <String>[];
    if (first != null && first.trim().isNotEmpty) parts.add(first.trim());
    if (last != null && last.trim().isNotEmpty) parts.add(last.trim());
    return parts.isEmpty ? fallback : parts.join(' ');
  }

  Future<void> _fetchUserMeFromApi() async {
    setState(() {
      _offline = false;
      _refreshing = true;
    });

    try {
      final token = await _getAuthToken();
      if (token.isEmpty) return;

      final base = await ApiConfig.readBase();
      final resp = await http.get(
        Uri.parse('$base/users/me'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final Map<String, dynamic> payload =
            decoded is Map && decoded['data'] is Map ? Map<String, dynamic>.from(decoded['data']) : (decoded is Map ? Map<String, dynamic>.from(decoded) : {});
        await _persistUserToPrefsFromApi(payload);
      } else {
        // don’t hard-fail; just show cached
        setState(() => _offline = true);
      }
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _onRefresh() async {
    await _hydrateFromFirebaseAuth();
    await _fetchUserMeFromApi();
  }

  // -------------------- PROFILE PHOTO (Firebase Storage) --------------------
  void _showPhotoSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadProfilePhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadProfilePhoto(ImageSource.gallery);
              },
            ),
            if (_photoUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.open_in_full),
                title: const Text('View photo'),
                onTap: () {
                  Navigator.pop(context);
                  _viewProfilePhoto();
                },
              ),
            if (_photoUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text('Remove photo'),
                onTap: () {
                  Navigator.pop(context);
                  _removeProfilePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadProfilePhoto(ImageSource source) async {
    final u = _auth.currentUser;
    if (u == null) {
      ToastHelper.showCustomToast(context, 'Please login first', isSuccess: false, errorMessage: '');
      return;
    }

    try {
      final x = await _picker.pickImage(source: source, maxWidth: 1400, imageQuality: 85);
      if (x == null) return;

      setState(() => _refreshing = true);

      final bytes = await x.readAsBytes();
      final mime = lookupMimeType(x.name, headerBytes: bytes.take(12).toList()) ?? 'image/jpeg';
      final ext = mime.contains('png') ? 'png' : 'jpg';

      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_photos/${u.uid}/${DateTime.now().millisecondsSinceEpoch}.$ext');

      await ref.putData(bytes, SettableMetadata(contentType: mime));
      final url = await ref.getDownloadURL();

      await u.updatePhotoURL(url);

      // Optional mirrors (ignore failures)
      try {
        await _firestore.collection('users').doc(u.uid).set({'photoURL': url, 'profilepicture': url}, SetOptions(merge: true));
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', url);

      if (!mounted) return;
      setState(() => _photoUrl = url);

      ToastHelper.showCustomToast(context, 'Profile photo updated', isSuccess: true, errorMessage: '');
    } catch (e) {
      ToastHelper.showCustomToast(context, 'Failed to update photo', isSuccess: false, errorMessage: e.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _viewProfilePhoto() {
    if (_photoUrl.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: InteractiveViewer(
            child: Image.network(
              _photoUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 260,
                child: Center(child: Icon(Icons.broken_image_outlined, size: 48)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _removeProfilePhoto() async {
    final u = _auth.currentUser;
    if (u == null) return;

    try {
      setState(() => _refreshing = true);

      await u.updatePhotoURL('');

      try {
        await _firestore.collection('users').doc(u.uid).set({'photoURL': '', 'profilepicture': ''}, SetOptions(merge: true));
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', '');

      if (!mounted) return;
      setState(() => _photoUrl = '');

      ToastHelper.showCustomToast(context, 'Photo removed', isSuccess: true, errorMessage: '');
    } catch (e) {
      ToastHelper.showCustomToast(context, 'Failed to remove photo', isSuccess: false, errorMessage: e.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // -------------------- EDIT PROFILE --------------------
  void _openEditProfile() async {
    final result = await showModalBottomSheet<_EditProfileResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditProfileSheet(
        name: _name,
        phone: _phone,
        address: _address,
      ),
    );

    if (result == null) return;

    try {
      setState(() => _refreshing = true);

      // Save locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fullName', result.name);
      await prefs.setString('name', result.name);
      await prefs.setString('phone', result.phone);
      await prefs.setString('address', result.address);

      setState(() {
        _name = result.name;
        _phone = result.phone;
        _address = result.address;
      });

      // Update Firebase displayName (best effort)
      final u = _auth.currentUser;
      if (u != null && result.name.trim().isNotEmpty) {
        await u.updateDisplayName(result.name.trim());
      }

      // Update API best-effort (if token exists)
      final token = await _getAuthToken();
      if (token.isNotEmpty) {
        final base = await ApiConfig.readBase();
        await http.put(
          Uri.parse('$base/users/me'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'name': result.name,
            'phone': result.phone,
            'address': result.address,
          }),
        );
      }

      ToastHelper.showCustomToast(context, 'Profile updated', isSuccess: true, errorMessage: '');
    } catch (e) {
      ToastHelper.showCustomToast(context, 'Update failed', isSuccess: false, errorMessage: e.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // -------------------- CHANGE PASSWORD --------------------
  void _openChangePassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChangePasswordModernPage()),
    );
  }

  // -------------------- MY ADDRESS --------------------
  void _openMyAddress() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MyAddressSheet(initialAddress: _address),
    );

    if (result == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('address', result);
    setState(() => _address = result);

    // optional mirror
    try {
      final u = _auth.currentUser;
      if (u != null) {
        await _firestore.collection('users').doc(u.uid).set({'address': result}, SetOptions(merge: true));
      }
    } catch (_) {}

    ToastHelper.showCustomToast(context, 'Address updated', isSuccess: true, errorMessage: '');
  }

  // -------------------- LOGOUT --------------------
  Future<void> _logout() async {
    final ok = await _confirm(
      title: 'Logout',
      message: 'Do you want to log out of this account?',
      confirmText: 'Logout',
      confirmColor: Colors.red,
    );
    if (ok != true) return;

    setState(() => _refreshing = true);
    try {
      final prefs = await SharedPreferences.getInstance();

      // clear common cached keys
      for (final k in [
        'jwt_token',
        'token',
        'authToken',
        'uid',
        'fullName',
        'name',
        'email',
        'phone',
        'address',
        'profilepicture',
      ]) {
        await prefs.remove(k);
      }

      await _auth.signOut();
    } catch (_) {
      // ignore
    } finally {
      if (!mounted) return;
      setState(() => _refreshing = false);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  // -------------------- DELETE ACCOUNT --------------------
  Future<void> _deleteAccount() async {
    final ok = await _confirm(
      title: 'Delete account',
      message:
          'This will permanently delete your account and sign you out.\n\nThis action cannot be undone.',
      confirmText: 'Delete',
      confirmColor: Colors.red,
    );
    if (ok != true) return;

    setState(() => _refreshing = true);

    try {
      // best-effort API deletion
      final token = await _getAuthToken();
      if (token.isNotEmpty) {
        final base = await ApiConfig.readBase();
        try {
          await http.delete(
            Uri.parse('$base/users/me'),
            headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
          );
        } catch (_) {}
      }

      // best-effort Firestore cleanup
      final u = _auth.currentUser;
      if (u != null) {
        try {
          await _firestore.collection('users').doc(u.uid).delete();
        } catch (_) {}
      }

      // delete Firebase user (may require recent login)
      if (u != null) {
        await u.delete();
      }

      // clear prefs
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Account deleted', isSuccess: true, errorMessage: '');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      // Most common: requires-recent-login
      ToastHelper.showCustomToast(
        context,
        'Delete failed',
        isSuccess: false,
        errorMessage: e.code == 'requires-recent-login'
            ? 'Please login again then try deleting your account.'
            : e.message ?? e.code,
      );
    } catch (e) {
      ToastHelper.showCustomToast(context, 'Delete failed', isSuccess: false, errorMessage: e.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText, style: TextStyle(color: confirmColor, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // -------------------- POLICY --------------------
  void _openPolicy() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PolicyPage()));
  }

  Future<void> _openPolicyUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: _brandNavy,
        foregroundColor: Colors.white,
        title: const Text('Settings'),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshing ? null : _onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          children: [
            if (_offline) _offlineBanner(),
            _profileCard(),

            const SizedBox(height: 14),
            _sectionTitle('Account'),
            _card([
              _SettingsTile(
                icon: Icons.edit_outlined,
                title: 'Edit profile',
                subtitle: 'Update your name, phone, and address',
                onTap: _openEditProfile,
              ),
              _SettingsTile(
                icon: Icons.location_on_outlined,
                title: 'My address',
                subtitle: _address,
                onTap: _openMyAddress,
              ),
            ]),

            const SizedBox(height: 14),
            _sectionTitle('Security'),
            _card([
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'Change password',
                subtitle: 'Update your account password',
                onTap: _openChangePassword,
              ),
            ]),

            const SizedBox(height: 14),
            _sectionTitle('Legal & Support'),
            _card([
              _SettingsTile(
                icon: Icons.policy_outlined,
                title: 'Privacy policy & Terms',
                subtitle: 'Read how your data is handled',
                onTap: _openPolicy,
              ),
              _SettingsTile(
                icon: Icons.open_in_new,
                title: 'Open policy website',
                subtitle: 'Optional external link',
                onTap: () => _openPolicyUrl('https://example.com/privacy'),
              ),
            ]),

            const SizedBox(height: 14),
            _sectionTitle('About'),
            _card([
              _SettingsTile(
                icon: Icons.info_outline,
                title: 'App version',
                subtitle: 'v$_appVersion ($_buildNumber)',
                onTap: () {},
                trailing: const SizedBox.shrink(),
              ),
              if (_uid.isNotEmpty)
                _SettingsTile(
                  icon: Icons.fingerprint,
                  title: 'User ID',
                  subtitle: _uid,
                  onTap: () {},
                  trailing: const SizedBox.shrink(),
                ),
            ]),

            const SizedBox(height: 14),
            _sectionTitle('Danger zone'),
            _card([
              _SettingsTile(
                icon: Icons.logout,
                title: 'Logout',
                subtitle: 'Sign out of this device',
                onTap: _logout,
                iconColor: Colors.red,
                titleColor: Colors.red,
              ),
              _SettingsTile(
                icon: Icons.delete_forever,
                title: 'Delete my account',
                subtitle: 'Permanently delete your account',
                onTap: _deleteAccount,
                iconColor: Colors.red,
                titleColor: Colors.red,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _offlineBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEDEE),
        border: Border.all(color: const Color(0xFFFFC9CD)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: Colors.red),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'You are offline or the server is unreachable. Showing cached info.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_brandNavy, _brandOrange.withOpacity(0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 10))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            GestureDetector(
              onTap: _showPhotoSheet,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 58,
                  height: 58,
                  color: Colors.white.withOpacity(0.15),
                  child: _photoUrl.isEmpty
                      ? const Icon(Icons.person, color: Colors.white, size: 30)
                      : Image.network(
                          _photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white, size: 30),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(Icons.phone_outlined, _phone),
                      _chip(Icons.location_on_outlined, _address),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'View photo',
              onPressed: _photoUrl.isEmpty ? null : _viewProfilePhoto,
              icon: const Icon(Icons.open_in_full, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const Divider(height: 0),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? iconColor;
  final Color? titleColor;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (iconColor ?? _SettingsPageState._brandOrange).withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: iconColor ?? _SettingsPageState._brandOrange),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: titleColor)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing ?? const Icon(Icons.chevron_right),
    );
  }
}

// -------------------- EDIT PROFILE SHEET --------------------
class _EditProfileResult {
  final String name;
  final String phone;
  final String address;
  const _EditProfileResult(this.name, this.phone, this.address);
}

class _EditProfileSheet extends StatefulWidget {
  final String name;
  final String phone;
  final String address;

  const _EditProfileSheet({
    required this.name,
    required this.phone,
    required this.address,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.text = widget.name == 'Guest User' ? '' : widget.name;
    _phone.text = widget.phone == 'No Phone' ? '' : widget.phone;
    _address.text = widget.address == 'No Address' ? '' : widget.address;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(999))),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(child: Text('Edit profile', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _SettingsPageState._brandOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                final n = _name.text.trim().isEmpty ? 'Guest User' : _name.text.trim();
                final p = _phone.text.trim().isEmpty ? 'No Phone' : _phone.text.trim();
                final a = _address.text.trim().isEmpty ? 'No Address' : _address.text.trim();
                Navigator.pop(context, _EditProfileResult(n, p, a));
              },
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------- MY ADDRESS SHEET --------------------
class _MyAddressSheet extends StatefulWidget {
  final String initialAddress;
  const _MyAddressSheet({required this.initialAddress});

  @override
  State<_MyAddressSheet> createState() => _MyAddressSheetState();
}

class _MyAddressSheetState extends State<_MyAddressSheet> {
  final _c = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c.text = widget.initialAddress == 'No Address' ? '' : widget.initialAddress;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(999))),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(child: Text('My address', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Address',
              hintText: 'Enter your delivery/location address',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _SettingsPageState._brandOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                final a = _c.text.trim().isEmpty ? 'No Address' : _c.text.trim();
                Navigator.pop(context, a);
              },
              child: const Text('Save address', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------- CHANGE PASSWORD (Modern) --------------------
class ChangePasswordModernPage extends StatefulWidget {
  const ChangePasswordModernPage({super.key});

  @override
  State<ChangePasswordModernPage> createState() => _ChangePasswordModernPageState();
}

class _ChangePasswordModernPageState extends State<ChangePasswordModernPage> {
  final _auth = FirebaseAuth.instance;

  final _newPass = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _hide1 = true;
  bool _hide2 = true;

  @override
  void dispose() {
    _newPass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p1 = _newPass.text;
    final p2 = _confirm.text;

    if (p1.length < 6) {
      ToastHelper.showCustomToast(context, 'Password too short', isSuccess: false, errorMessage: 'Minimum 6 characters');
      return;
    }
    if (p1 != p2) {
      ToastHelper.showCustomToast(context, 'Passwords do not match', isSuccess: false, errorMessage: '');
      return;
    }

    final u = _auth.currentUser;
    if (u == null) {
      ToastHelper.showCustomToast(context, 'Please login first', isSuccess: false, errorMessage: '');
      return;
    }

    setState(() => _busy = true);
    try {
      await u.updatePassword(p1);
      ToastHelper.showCustomToast(context, 'Password updated', isSuccess: true, errorMessage: '');
      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Failed',
        isSuccess: false,
        errorMessage: e.code == 'requires-recent-login'
            ? 'Please login again then change password.'
            : (e.message ?? e.code),
      );
    } catch (e) {
      ToastHelper.showCustomToast(context, 'Failed', isSuccess: false, errorMessage: e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: _SettingsPageState._brandNavy,
        foregroundColor: Colors.white,
        title: const Text('Change password'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _newPass,
                obscureText: _hide1,
                decoration: InputDecoration(
                  labelText: 'New password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_hide1 ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _hide1 = !_hide1),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: _hide2,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_hide2 ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _hide2 = !_hide2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _SettingsPageState._brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Update password', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------- POLICY PAGE --------------------
class PolicyPage extends StatelessWidget {
  const PolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: _SettingsPageState._brandNavy,
        foregroundColor: Colors.white,
        title: const Text('Privacy & Terms'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                SizedBox(height: 8),
                Text(
                  '• We store basic account details (name, email, phone, address) to run the app.\n'
                  '• Profile photos are stored securely and used only to display your profile.\n'
                  '• You can request deletion anytime from Settings → Delete my account.\n',
                  style: TextStyle(height: 1.35),
                ),
                SizedBox(height: 14),
                Text('Terms & Conditions', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                SizedBox(height: 8),
                Text(
                  '• Use the app responsibly.\n'
                  '• Do not upload illegal content.\n'
                  '• We may update these terms as features change.\n',
                  style: TextStyle(height: 1.35),
                ),
                SizedBox(height: 10),
                Text(
                  'Replace this text with your official policy/terms (or load from your website).',
                  style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

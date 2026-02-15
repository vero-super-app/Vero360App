#!/usr/bin/env python3
"""Patch accommodation_merchant_dashboard.dart to match marketplace profile upload flow."""
import glob
import re

path = glob.glob('**/accommodation_merchant_dashboard.dart', recursive=True)[0]
with open(path, 'r', encoding='utf-8') as f:
    s = f.read()

# 1. Insert _getBearerTokenForApi and _uploadProfileViaBackend before _uploadProfileToFirebaseStorage
if '_getBearerTokenForApi' not in s:
    needle = "  Future<String> _uploadProfileToFirebaseStorage(String uid, XFile file) async {"
    methods = '''
  Future<String?> _getBearerTokenForApi({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && forceRefresh) {
      try {
        final idToken = await user.getIdToken(true);
        final t = idToken?.trim();
        if (t != null && t.isNotEmpty) return t;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.getString('jwt_token') ??
        prefs.getString('token') ??
        prefs.getString('authToken') ??
        prefs.getString('jwt');
    if (fromPrefs != null && fromPrefs.trim().isNotEmpty) {
      return fromPrefs.trim();
    }
    if (user == null) return null;
    try {
      final idToken = await user.getIdToken(forceRefresh);
      final t = idToken?.trim();
      if (t == null || t.isEmpty) return null;
      return t;
    } catch (_) {
      return null;
    }
  }

  Future<String> _uploadProfileViaBackend(XFile file) async {
    String bearer = await _getBearerTokenForApi(forceRefresh: true) ?? '';
    if (bearer.isEmpty) throw Exception('Not authenticated');
    final uri = ApiConfig.endpoint('/users/me/profile-picture');
    final bytes = await file.readAsBytes();
    final mimeType = lookupMimeType(file.name, headerBytes: bytes) ?? 'image/jpeg';
    final parts = mimeType.split('/');
    final contentType = parts.length == 2 ? MediaType(parts[0], parts[1]) : null;
    Future<http.StreamedResponse> sendRequest(String token) async {
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name.isNotEmpty ? file.name : 'profile.jpg',
          contentType: contentType,
        ));
      return req.send();
    }
    var sent = await sendRequest(bearer);
    var resp = await http.Response.fromStream(sent);
    if (resp.statusCode == 401) {
      bearer = await _getBearerTokenForApi(forceRefresh: true) ?? '';
      if (bearer.isEmpty) throw Exception('Session expired. Please sign in again.');
      sent = await sendRequest(bearer);
      resp = await http.Response.fromStream(sent);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (resp.statusCode == 404) throw Exception('Profile picture endpoint not found');
      if (resp.statusCode == 401) throw Exception('Session expired. Please sign in again.');
      throw Exception('Upload failed (${resp.statusCode}) ${resp.body}');
    }
    final body = jsonDecode(resp.body);
    final data = (body is Map && body['data'] is Map)
        ? body['data'] as Map
        : (body is Map ? Map<String, dynamic>.from(body as Map) : <String, dynamic>{});
    final url = (data['profilepicture'] ?? data['profilePicture'] ?? data['url'])?.toString();
    if (url == null || url.isEmpty) throw Exception('No URL in response');
    return url;
  }

  Future<String> _uploadProfileToFirebaseStorage(String uid, XFile file) async {'''
    s = s.replace(needle, methods, 1)
    print('Inserted _getBearerTokenForApi and _uploadProfileViaBackend')
else:
    print('Methods already present')

# 2. Replace _pickAndUploadProfile
old_pick = '''  Future<void> _pickAndUploadProfile(ImageSource src) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final file = await _picker.pickImage(
      source: src,
      maxWidth: 1400,
      imageQuality: 85,
    );
    if (file == null) return;
    try {
      setState(() => _profileUploading = true);
      final url = await _uploadProfileToFirebaseStorage(user.uid, file);
      await user.updatePhotoURL(url);
      await user.reload();
      await _firestore.collection('users').doc(user.uid).set({
        'profilePicture': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _merchantProfileUrl = url);
      ToastHelper.showCustomToast(context, 'Profile picture updated', isSuccess: true, errorMessage: '');
    } catch (e) {
      debugPrint('Profile upload error: $e');
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Failed to upload photo', isSuccess: false, errorMessage: '');
    } finally {
      if (mounted) setState(() => _profileUploading = false);
    }
  }'''

new_pick = '''  Future<void> _pickAndUploadProfile(ImageSource src) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final file = await _picker.pickImage(
      source: src,
      maxWidth: 1400,
      imageQuality: 85,
    );
    if (file == null) return;
    try {
      setState(() => _profileUploading = true);
      String url;
      try {
        url = await _uploadProfileViaBackend(file);
      } catch (backendErr) {
        debugPrint('Backend profile upload failed: $backendErr');
        try {
          url = await _uploadProfileToFirebaseStorage(user.uid, file);
        } on FirebaseException catch (e) {
          if ((e.code == 'object-not-found' || e.code == 'unknown') && (e.message?.contains('404') == true)) {
            url = await _uploadProfileViaBackend(file);
          } else {
            rethrow;
          }
        }
      }
      await user.updatePhotoURL(url);
      await user.reload();
      await _firestore.collection('users').doc(user.uid).set({
        'profilePicture': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', url);
      if (!mounted) return;
      setState(() => _merchantProfileUrl = url);
      ToastHelper.showCustomToast(context, 'Profile picture updated', isSuccess: true, errorMessage: '');
    } on FirebaseException catch (e) {
      debugPrint('Profile upload error: ${e.code} ${e.message}');
      if (!mounted) return;
      try {
        final url = await _uploadProfileViaBackend(file);
        if (url.isNotEmpty) {
          final u = _auth.currentUser;
          if (u != null) {
            await u.updatePhotoURL(url);
            await u.reload();
            await _firestore.collection('users').doc(u.uid).set({
              'profilePicture': url,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('profilepicture', url);
            if (mounted) setState(() => _merchantProfileUrl = url);
            ToastHelper.showCustomToast(context, 'Profile picture updated', isSuccess: true, errorMessage: '');
            return;
          }
        }
      } catch (fallbackErr) {
        debugPrint('Backend fallback failed: $fallbackErr');
      }
      if (e.code == 'object-not-found' || (e.message ?? '').contains('404')) {
        ToastHelper.showCustomToast(context, 'Upload failed. Check network and that the server is running.', isSuccess: false, errorMessage: '');
      } else {
        ToastHelper.showCustomToast(context, 'Failed to upload photo. Please try again.', isSuccess: false, errorMessage: '');
      }
    } catch (e) {
      debugPrint('Profile upload error: $e');
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Failed to upload photo. Please try again.', isSuccess: false, errorMessage: '');
    } finally {
      if (mounted) setState(() => _profileUploading = false);
    }
  }'''

new_pick = new_pick.replace('\\$', '$')

if old_pick in s:
    s = s.replace(old_pick, new_pick, 1)
    print('Replaced _pickAndUploadProfile')
else:
    print('_pickAndUploadProfile block not found')

# 3. Update _removeProfilePhoto to add SharedPreferences
old_remove = '''      await _firestore.collection('users').doc(user.uid).set({
        'profilePicture': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _merchantProfileUrl = '');'''

new_remove = '''      await _firestore.collection('users').doc(user.uid).set({
        'profilePicture': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', '');
      if (!mounted) return;
      setState(() => _merchantProfileUrl = '');'''

if old_remove in s:
    s = s.replace(old_remove, new_remove, 1)
    print('Updated _removeProfilePhoto with SharedPreferences')

with open(path, 'w', encoding='utf-8') as f:
    f.write(s)
print('Done:', path)

  import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/config/api_config.dart';

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

  /// Upload via backend POST /vero/users/me/profile-picture.
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

  // ignore: unused_element
  Future<String> _uploadProfileToFirebaseStorage(String uid, XFile file) async {
    // TODO: Implement actual upload logic. Example placeholder:
    try {
      // Simulate an upload delay (remove this in production)
      await Future.delayed(const Duration(milliseconds: 200));
      // Return a fake URL for demonstration; replace with actual upload logic.
      return 'https://firebase.storage.fakeurl.com/user/$uid/profile/${file.name}';
    } catch (e) {
      throw Exception('Failed to upload profile to Firebase Storage: $e');
    }
  }
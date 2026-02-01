// lib/services/merchantform.service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/utils/toasthelper.dart';

class ServiceProviderService {
  // Kept for compatibility, but not used (we rely on ApiConfig inside).
  final String baseUrl;
  ServiceProviderService({required this.baseUrl});

  /// Multipart POST /serviceprovider
  Future<bool> submitServiceProviderMultipart({
    required Map<String, String> fields,
    required XFile nationalIdFile,
    XFile? logoFile,
    required BuildContext context,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('jwt_token') ?? prefs.getString('token') ?? '';
      if (token.isEmpty) {
        ToastHelper.showCustomToast(
          context,
          'Please log in again',
          isSuccess: false,
          errorMessage: '',
        );
        return false;
      }

      // Strict whitelist for fields to avoid "should not exist"
      final allowed = <String>{
        'businessName',
        'businessDescription',
        'openingHours',
        'status',
      };
      final sanitized = <String, String>{};
      fields.forEach((k, v) {
        final trimmed = v.trim();
        if (allowed.contains(k) && trimmed.isNotEmpty) {
          sanitized[k] = trimmed;
        }
      });

      final uri = ApiConfig.endpoint('/serviceprovider');
      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'accept': '*/*',
        })
        ..fields.addAll(sanitized);

      // Attach files with correct field names
      if (kIsWeb) {
        final bytes = await nationalIdFile.readAsBytes();
        req.files.add(http.MultipartFile.fromBytes(
          'nationalIdImage',
          bytes,
          filename: nationalIdFile.name.isEmpty
              ? 'national-id.jpg'
              : nationalIdFile.name,
        ));
        if (logoFile != null) {
          final lbytes = await logoFile.readAsBytes();
          req.files.add(http.MultipartFile.fromBytes(
            'logoimage',
            lbytes,
            filename: logoFile.name.isEmpty ? 'logo.jpg' : logoFile.name,
          ));
        }
      } else {
        req.files.add(await http.MultipartFile.fromPath(
          'nationalIdImage',
          nationalIdFile.path,
        ));
        if (logoFile != null) {
          req.files.add(await http.MultipartFile.fromPath(
            'logoimage',
            logoFile.path,
          ));
        }
      }

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode == 200 || res.statusCode == 201) {
        return true;
      }

      String message = _extractMessage(res.body);
      if (res.statusCode == 413) {
        message = 'Images are too large. Please pick a smaller photo.';
      }

      ToastHelper.showCustomToast(
        context,
        message,
        isSuccess: false,
        errorMessage: '',
      );
      return false;
    } catch (e) {
      if (kIsWeb) {
        debugPrint('submitServiceProviderMultipart error: $e');
      }
      ToastHelper.showCustomToast(
        context,
        'Network error. Please check your connection and try again.',
        isSuccess: false,
        errorMessage: '',
      );
      return false;
    }
  }

  String _extractMessage(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map) {
        final m = parsed['message'];
        if (m is List && m.isNotEmpty) return m.first.toString();
        if (m is String) return m;
        if (parsed['error'] != null) return parsed['error'].toString();
      }
      if (parsed is List && parsed.isNotEmpty) {
        return parsed.first.toString();
      }
    } catch (_) {}
    return 'Failed to submit. Please check your details and try again.';
  }
}

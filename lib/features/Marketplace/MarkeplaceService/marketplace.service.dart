// lib/services/marketplace_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/config/api_config.dart';

class MarketplaceService {
  // ---------- auth helpers ----------

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ??
        prefs.getString('token') ??
        prefs.getString('jwt');
  }

  Map<String, String> _authHeaders(
    String? token, {
    Map<String, String>? extra,
  }) =>
      {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        ...?extra,
      };

  /// For multipart responses only (uploads / photo search).
  /// No URL in the error message.
  dynamic _decodeOrThrowMultipart(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      String msg = 'Request failed. Please try again.';

      if (kDebugMode) {
        debugPrint('Multipart error status: ${r.statusCode}');
        debugPrint('Multipart error body: ${r.body}');
      }

      try {
        final body = jsonDecode(r.body);
        if (body is Map && body['message'] != null) {
          final m = body['message'];
          if (m is List && m.isNotEmpty) {
            msg = m.first.toString();
          } else {
            msg = m.toString();
          }
        }
      } catch (_) {}
      throw ApiException(message: msg, statusCode: r.statusCode);
    }

    if (r.body.isEmpty) return const {};
    try {
      return jsonDecode(r.body);
    } catch (_) {
      throw const ApiException(
        message: 'Invalid response from server. Please try again.',
      );
    }
  }

  String _safeDefaultNameFromMime(String mime) {
    if (mime.contains('png')) return 'upload.png';
    if (mime.contains('webp')) return 'upload.webp';
    if (mime.contains('heic') || mime.contains('heif')) return 'upload.heic';
    if (mime.contains('gif')) return 'upload.gif';
    if (mime.startsWith('video/')) return 'upload.mp4';
    return 'upload.jpg';
  }

  // ========= UPLOADS =========

  /// Upload from BYTES (works for HEIC and temp files that disappear).
  /// Uses API endpoint (/vero/uploads) so it hits Nest, not bare root.
  Future<String> uploadBytes(
    Uint8List bytes, {
    required String filename,
    String? mimeType,
  }) async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Please sign in before uploading.',
      );
    }

    // IMPORTANT: go through API base (e.g. https://domain/vero/uploads)
    final uri = ApiConfig.endpoint('/uploads');

    final detectedMime =
        mimeType ?? lookupMimeType(filename, headerBytes: bytes);
    final safeName = filename.isNotEmpty
        ? filename
        : _safeDefaultNameFromMime(detectedMime ?? '');

    if (kDebugMode) {
      debugPrint('Uploading bytes -> $uri');
      debugPrint('Filename: $safeName, mime: $detectedMime');
    }

    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders(token, extra: {
        'Accept': 'application/json',
      }))
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: safeName,
        contentType:
            detectedMime != null ? MediaType.parse(detectedMime) : null,
      ));

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (kDebugMode) {
      debugPrint('UploadBytes status: ${resp.statusCode}');
    }

    final body = _decodeOrThrowMultipart(resp);
    final url = body is Map ? body['url']?.toString() : null;

    if (url == null || url.isEmpty) {
      throw const ApiException(
        message: 'Upload succeeded but no image URL was returned.',
      );
    }
    return url;
  }

  /// Upload from file path (mobile/desktop).
  Future<String> uploadImageFile(
    File imageFile, {
    String filename = 'upload.jpg',
  }) async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Please sign in before uploading.',
      );
    }

    // IMPORTANT: use API base so it reaches /vero/uploads
    final uri = ApiConfig.endpoint('/uploads');

    if (kDebugMode) {
      debugPrint('Uploading file -> $uri');
      debugPrint('Path: ${imageFile.path}, filename: $filename');
    }

    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders(token, extra: {
        'Accept': 'application/json',
      }))
      ..files.add(await http.MultipartFile.fromPath(
        'file',
        imageFile.path,
        filename: filename,
        contentType: MediaType('image', 'jpeg'),
      ));

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (kDebugMode) {
      debugPrint('UploadImageFile status: ${resp.statusCode}');
    }

    final body = _decodeOrThrowMultipart(resp);
    final url = body is Map ? body['url']?.toString() : null;

    if (url == null || url.isEmpty) {
      throw const ApiException(
        message: 'Upload succeeded but no image URL was returned.',
      );
    }
    return url;
  }

  // ========= SECURED (owner enforced server-side) =========

  /// CREATE marketplace item.
  Future<MarketplaceDetailModel> createItem(MarketplaceItem item) async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'You must be signed in to create items.',
      );
    }

    try {
      final res = await ApiClient.post(
        '/marketplace',
        headers: _authHeaders(token),
        body: jsonEncode(item.toJson()),
      );

      final body = jsonDecode(res.body);
      final data = (body is Map && body['data'] is Map)
          ? body['data'] as Map<String, dynamic>
          : (body as Map<String, dynamic>);

      return MarketplaceDetailModel.fromJson(data);
    } on ApiException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('createItem error: $e');
      throw const ApiException(
        message:
            'Could not create item. Please check your details and try again.',
      );
    }
  }

  /// UPDATE marketplace item.
  Future<MarketplaceDetailModel> updateItem(
      int id, Map<String, dynamic> patch) async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'You must be signed in to update items.',
      );
    }

    try {
      final res = await ApiClient.put(
        '/marketplace/$id',
        headers: _authHeaders(token),
        body: jsonEncode(patch),
      );

      final body = jsonDecode(res.body);
      final data = (body is Map && body['data'] is Map)
          ? body['data'] as Map<String, dynamic>
          : (body as Map<String, dynamic>);

      return MarketplaceDetailModel.fromJson(data);
    } on ApiException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('updateItem error: $e');
      throw const ApiException(
        message: 'Could not update item. Please try again.',
      );
    }
  }

  /// DELETE /marketplace/:id
  Future<void> deleteItem(int id) async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'You must be signed in to delete items.',
      );
    }

    try {
      await ApiClient.delete(
        '/marketplace/$id',
        headers: _authHeaders(token),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('deleteItem error: $e');
      throw const ApiException(
        message: 'Could not delete item. Please try again.',
      );
    }
  }

  // ========= PUBLIC =========

  /// ONLY my items -> GET /marketplace/me
  Future<List<MarketplaceDetailModel>> fetchMyItems() async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      if (kDebugMode) debugPrint('fetchMyItems: no token');
      return [];
    }

    try {
      final res = await ApiClient.get(
        '/marketplace/me',
        headers: _authHeaders(token, extra: {'Accept': 'application/json'}),
      );

      final body = jsonDecode(res.body);
      final list = body is Map ? body['data'] : body;

      if (list is List) {
        return list
            .map((e) => MarketplaceDetailModel.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      return [];
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('fetchMyItems ApiException: ${e.message}');
      return [];
    } catch (e) {
      if (kDebugMode) debugPrint('fetchMyItems error: $e');
      return [];
    }
  }

  /// Photo search => POST /marketplace/search/photo
  Future<List<MarketplaceDetailModel>> searchByPhoto(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return searchByPhotoBytes(bytes, filename: imageFile.path.split('/').last);
  }

  /// Photo search from bytes (works with XFile, content URIs, etc.)
  Future<List<MarketplaceDetailModel>> searchByPhotoBytes(
    Uint8List bytes, {
    String filename = 'photo.jpg',
  }) async {
    try {
      await ApiConfig.init();
      final uri = ApiConfig.endpoint('/marketplace/search/photo');
      final ext = filename.toLowerCase().split('.').last;
      MediaType contentType;
      if (ext == 'png') {
        contentType = MediaType('image', 'png');
      } else if (ext == 'webp') {
        contentType = MediaType('image', 'webp');
      } else {
        contentType = MediaType('image', 'jpeg');
      }
      final req = http.MultipartRequest('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..files.add(http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: filename,
          contentType: contentType,
        ));

      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamed);
      final body = _decodeOrThrowMultipart(resp);
      final list = body is Map ? body['data'] : body;

      if (list is List) {
        return list
            .map((e) => MarketplaceDetailModel.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      return [];
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('searchByPhoto ApiException: ${e.message}');
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('searchByPhoto error: $e');
      rethrow;
    }
  }

  /// Name search => GET /marketplace/search/:name
  Future<List<MarketplaceDetailModel>> searchByName(String name) async {
    try {
      final safe = Uri.encodeComponent(name.trim());
      final path = '/marketplace/search/$safe';

      final res = await ApiClient.get(path);

      final body = jsonDecode(res.body);
      final list = body is Map ? body['data'] : body;

      if (list is List) {
        return list
            .map((e) => MarketplaceDetailModel.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      return [];
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('searchByName ApiException: ${e.message}');
      return [];
    } catch (e) {
      if (kDebugMode) debugPrint('searchByName error: $e');
      return [];
    }
  }

  /// Details => GET /marketplace/:id
  Future<MarketplaceDetailModel?> getItemDetails(int itemId) async {
    try {
      final res = await ApiClient.get('/marketplace/$itemId');
      final body = jsonDecode(res.body);

      final data = body is Map ? body['data'] : body;
      if (data == null) return null;

      return MarketplaceDetailModel.fromJson(
        Map<String, dynamic>.from(data as Map),
      );
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('getItemDetails ApiException: ${e.message}');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('getItemDetails error: $e');
      return null;
    }
  }

  /// List (optionally filtered by category) => GET /marketplace[?category=...]
  Future<List<MarketplaceDetailModel>> fetchMarketItems(
      {String? category}) async {
    try {
      var path = '/marketplace';
      if (category != null && category.trim().isNotEmpty) {
        path +=
            '?category=${Uri.encodeComponent(category.trim().toLowerCase())}';
      }

      final res = await ApiClient.get(path);
      final body = jsonDecode(res.body);
      final list = body is Map ? body['data'] : body;

      if (list is List) {
        return list
            .map((e) => MarketplaceDetailModel.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      return [];
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('fetchMarketItems ApiException: ${e.message}');
      return [];
    } catch (e) {
      if (kDebugMode) debugPrint('fetchMarketItems error: $e');
      return [];
    }
  }
}

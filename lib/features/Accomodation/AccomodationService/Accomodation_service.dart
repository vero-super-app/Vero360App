import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

String _multipartUploadErrorMessage(http.Response resp) {
  try {
    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['message'] != null) {
      final m = decoded['message'];
      if (m is List && m.isNotEmpty) return m.first.toString();
      return m.toString();
    }
  } catch (_) {}
  return 'Image upload failed (${resp.statusCode}).';
}

/// Nest `@MaxLength(2048)` on `image` — presigned URLs often exceed that; strip `?…` / `#…`.
/// Rejects `data:…` / huge non-URL blobs (misconfigured upload API).
String _normalizeAccommodationImageRef(String raw) {
  const maxLen = 2048;
  var s = raw.trim();
  if (s.isEmpty) {
    throw const ApiException(message: 'Image URL is required.');
  }
  if (s.startsWith('data:')) {
    throw const ApiException(
      message:
          'The upload API returned inline base64 (data:…) instead of a link. '
          'Change POST /vero/uploads to respond with a short https URL in `url`.',
    );
  }
  final lower = s.toLowerCase();
  final isHttp = lower.startsWith('http://') || lower.startsWith('https://');
  if (s.length > maxLen && !isHttp) {
    throw const ApiException(
      message:
          'The upload API did not return a web URL. The `url` field must be https://… '
          '(not raw base64 or a data URL).',
    );
  }
  if (s.length <= maxLen) return s;

  var cut = s;
  final q = cut.indexOf('?');
  if (q >= 0) cut = cut.substring(0, q);
  final h = cut.indexOf('#');
  if (h >= 0) cut = cut.substring(0, h);
  if (cut.length <= maxLen) return cut;

  throw ApiException(
    message:
        'Image URL is still too long after removing ?query (${cut.length} chars; max $maxLen). '
        'Return a shorter public URL from uploads or raise the limit on the server.',
  );
}

MediaType _parseMediaTypeSafe(String mime) {
  try {
    return MediaType.parse(mime);
  } catch (_) {
    return MediaType('image', 'jpeg');
  }
}

List<Accommodation> _decodeAccommodationList(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) {
    throw const ApiException(
      message: 'Unexpected response format from server.',
    );
  }
  return decoded
      .map<Accommodation>(
        (e) => Accommodation.fromJson(Map<String, dynamic>.from(e)),
      )
      .toList();
}

class AccommodationService {
  /// `POST /vero/uploads` — same token source as [ApiClient]. Validates `url` is https, not base64.
  Future<String> uploadListingImage(
    Uint8List bytes, {
    required String filename,
    String? mimeType,
  }) async {
    final token = await AuthHandler.getTokenForApi();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Please sign in before uploading images.',
      );
    }
    final uri = ApiConfig.endpoint('/uploads');
    final detected =
        mimeType ?? lookupMimeType(filename, headerBytes: bytes) ?? 'image/jpeg';
    final safeName = filename.trim().isEmpty ? 'photo.jpg' : filename.trim();

    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      })
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: safeName,
        contentType: _parseMediaTypeSafe(detected),
      ));

    final http.Response resp;
    try {
      final streamed =
          await req.send().timeout(const Duration(seconds: 120));
      resp = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(
        message: 'Image upload timed out. Check your connection and try again.',
      );
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(
        message: _multipartUploadErrorMessage(resp),
        statusCode: resp.statusCode,
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      throw const ApiException(
        message: 'Invalid response from image upload.',
      );
    }
    if (decoded is! Map) {
      throw const ApiException(
        message: 'Upload response was not valid JSON.',
      );
    }
    final map = Map<String, dynamic>.from(decoded);
    final url = map['url']?.toString().trim();
    if (url == null || url.isEmpty) {
      throw const ApiException(
        message: 'Upload succeeded but the server did not return `url`.',
      );
    }
    return _normalizeAccommodationImageRef(url);
  }

  Future<List<Accommodation>> fetch({
    String? type, // hotel, lodge, bnb, house, hostel, apartment
    /// District name / address text, or a numeric location id for `/by-location`.
    String? location,
  }) async {
    try {
      final loc = location?.trim() ?? '';
      final locIsNumeric = loc.isNotEmpty && RegExp(r'^\d+$').hasMatch(loc);

      final typeFilter = type != null &&
          type.isNotEmpty &&
          type.toLowerCase() != 'all';
      var t = (type ?? '').toLowerCase().trim();
        if (t == 'apartments') t = 'apartment';
        if (t == 'houses') t = 'house';

      // `/by-location` validates `location` as a numeric id (Nest ParseIntPipe).
      if (loc.isNotEmpty && locIsNumeric) {
        final res = await ApiClient.get(
          '/accommodations/by-location',
          queryParameters: {'location': loc},
        );
        var list = _decodeAccommodationList(res.body);
        if (typeFilter) {
          list = list
              .where(
                (a) => a.accommodationType.toLowerCase() == t,
              )
              .toList();
        }
        return list;
      }

      // Text location: load by type (or all), then match `location` field locally.
      if (loc.isNotEmpty && !locIsNumeric) {
        final http.Response res;
        if (typeFilter) {
          res = await ApiClient.get(
            '/accommodations',
            queryParameters: {'type': t},
          );
        } else {
          res = await ApiClient.get('/accommodations/all');
        }
        final list = _decodeAccommodationList(res.body);
        final q = loc.toLowerCase();
        return list
            .where((a) => a.location.toLowerCase().contains(q))
            .toList();
      }

      if (typeFilter) {
        final res = await ApiClient.get(
          '/accommodations',
          queryParameters: {'type': t},
        );
        return _decodeAccommodationList(res.body);
      }

      final res = await ApiClient.get('/accommodations/all');
      return _decodeAccommodationList(res.body);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        message: 'Unable to load accommodations. Please try again.',
      );
    }
  }

  /// POST `/vero/accommodations` — `image` and `gallery` must be short strings
  /// (e.g. URLs from `POST /vero/uploads`), not base64 blobs.
  Future<Map<String, dynamic>> createAccommodation({
    required String name,
    required String location,
    required String description,
    required num pricePerNight,
    int capacity = 1,
    String pricingPeriod = 'night',
    required String accommodationType,
    String? hostelGender,
    String? roomType,
    bool? isAvailable,
    required String image,
    List<String> gallery = const [],
  }) async {
    final normalizedImage = _normalizeAccommodationImageRef(image);
    final normalizedGallery = gallery
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map(_normalizeAccommodationImageRef)
        .toList();

    final period = pricingPeriod.trim().toLowerCase();
    final normalizedPeriod =
        period == 'day' || period == 'month' ? period : 'night';
    final normalizedCapacity = capacity < 1 ? 1 : capacity;

    final body = jsonEncode({
      'name': name,
      'location': location,
      'description': description,
      'pricePerNight': pricePerNight,
      'capacity': normalizedCapacity,
      'pricingPeriod': normalizedPeriod,
      'accommodationType': accommodationType.toLowerCase().trim(),
      if (hostelGender != null && hostelGender.trim().isNotEmpty)
        'hostelGender': hostelGender.trim().toLowerCase(),
      if (roomType != null && roomType.trim().isNotEmpty)
        'roomType': roomType.trim().toLowerCase(),
      if (isAvailable != null) 'isAvailable': isAvailable,
      'image': normalizedImage,
      'gallery': normalizedGallery,
    });

    // Large JSON (cover + gallery as base64) needs more than the default 20s.
    final res = await ApiClient.post(
      '/accommodations',
      body: body,
      timeout: const Duration(seconds: 120),
    );
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {};
  }

  /// PUT `/vero/accommodations/:id` — same payload shape as [createAccommodation].
  Future<Map<String, dynamic>> updateAccommodation({
    required int id,
    required String name,
    required String location,
    required String description,
    required num pricePerNight,
    int capacity = 1,
    String pricingPeriod = 'night',
    required String accommodationType,
    String? hostelGender,
    String? roomType,
    bool? isAvailable,
    required String image,
    List<String> gallery = const [],
  }) async {
    final normalizedImage = _normalizeAccommodationImageRef(image);
    final normalizedGallery = gallery
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map(_normalizeAccommodationImageRef)
        .toList();

    final period = pricingPeriod.trim().toLowerCase();
    final normalizedPeriod =
        period == 'day' || period == 'month' ? period : 'night';
    final normalizedCapacity = capacity < 1 ? 1 : capacity;

    final body = jsonEncode({
      'name': name,
      'location': location,
      'description': description,
      'pricePerNight': pricePerNight,
      'capacity': normalizedCapacity,
      'pricingPeriod': normalizedPeriod,
      'accommodationType': accommodationType.toLowerCase().trim(),
      if (hostelGender != null && hostelGender.trim().isNotEmpty)
        'hostelGender': hostelGender.trim().toLowerCase(),
      if (roomType != null && roomType.trim().isNotEmpty)
        'roomType': roomType.trim().toLowerCase(),
      if (isAvailable != null) 'isAvailable': isAvailable,
      'image': normalizedImage,
      'gallery': normalizedGallery,
    });

    final res = await ApiClient.put(
      '/accommodations/$id',
      body: body,
      timeout: const Duration(seconds: 120),
    );
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {};
  }

  /// DELETE `/vero/accommodations/:id`
  Future<void> deleteAccommodation(int id) async {
    await ApiClient.delete(
      '/accommodations/$id',
      timeout: const Duration(seconds: 30),
    );
  }

  /// Lists accommodations from `/accommodations/all` owned by [ownerEmail] (case-insensitive).
  Future<List<Accommodation>> fetchOwnedByEmail(String ownerEmail) async {
    final e = ownerEmail.trim().toLowerCase();
    if (e.isEmpty) return [];
    final all = await fetch();
    return all
        .where((a) => (a.owner?.email ?? '').trim().toLowerCase() == e)
        .toList();
  }

  // Optional compatibility method
  Future<List<Accommodation>> fetchAll() => fetch();
}
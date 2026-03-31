// lib/services/marketplace_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io' show File;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  static const int _noVisualDistance = 999;
  static const int _strongVisualThreshold = 18; // very close visual match
  static const int _softVisualThreshold = 24; // still similar
  static const int _maxPhotoResults = 60; // keep UI focused/fast
  static const int _deriveLimitPerSearch = 10; // cap expensive hash derivations
  static const Duration _deriveTimeout = Duration(milliseconds: 3500);
  final Map<String, String> _derivedHashMemo = <String, String>{};

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

  /// Mark an item as sold (sets isActive = false).
  Future<void> markItemSold(int id) async {
    // We deliberately ignore the returned object; callers only care that the flag was updated.
    await updateItem(id, {'isActive': false});
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

  /// Photo search from a picked file.
  Future<List<MarketplaceDetailModel>> searchByPhoto(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return searchByPhotoBytes(bytes, filename: imageFile.path.split('/').last);
  }

  int _stablePositiveIdFromString(String s) {
    int hash = 0;
    for (final code in s.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    if (hash == 0) hash = 1;
    return hash;
  }

  List<String> _parseStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
    }
    if (v is String) {
      final raw = v.trim();
      if (raw.isEmpty) return const <String>[];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((e) => '$e'.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {}
      return raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  MarketplaceDetailModel _fromFirestoreDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};

    final image = (data['image'] ??
            data['imageUrl'] ??
            data['photo'] ??
            data['picture'] ??
            '')
        .toString()
        .trim();

    final galleryA = _parseStringList(data['gallery']);
    final galleryB = _parseStringList(data['galleryUrls']);
    final seen = <String>{};
    final gallery = <String>[];
    for (final g in [...galleryA, ...galleryB]) {
      final x = g.trim();
      if (x.isEmpty || seen.contains(x)) continue;
      seen.add(x);
      gallery.add(x);
    }

    double price = 0;
    final p = data['price'];
    if (p is num) {
      price = p.toDouble();
    } else if (p != null) {
      price = double.tryParse(p.toString()) ?? 0;
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString().replaceAll(RegExp(r'[^\d]'), ''));
    }

    final sqlId =
        parseInt(data['sqlItemId'] ?? data['backendId'] ?? data['itemId'] ?? data['id']);
    final id = sqlId ?? _stablePositiveIdFromString(doc.id);

    DateTime? createdAt;
    final createdRaw = data['createdAt'];
    if (createdRaw is Timestamp) {
      createdAt = createdRaw.toDate();
    } else if (createdRaw is DateTime) {
      createdAt = createdRaw;
    } else if (createdRaw != null) {
      createdAt = DateTime.tryParse(createdRaw.toString());
    }

    return MarketplaceDetailModel(
      id: id,
      name: (data['name'] ?? '').toString(),
      image: image,
      price: price,
      description: (data['description'] ?? '').toString(),
      location: (data['location'] ?? '').toString(),
      category: data['category']?.toString(),
      gallery: gallery,
      videos: _parseStringList(data['videos']),
      sellerBusinessName: data['sellerBusinessName']?.toString(),
      sellerOpeningHours: data['sellerOpeningHours']?.toString(),
      sellerStatus: data['sellerStatus']?.toString(),
      sellerBusinessDescription: data['sellerBusinessDescription']?.toString(),
      sellerRating: (data['sellerRating'] is num)
          ? (data['sellerRating'] as num).toDouble()
          : double.tryParse('${data['sellerRating']}'),
      sellerLogoUrl: data['sellerLogoUrl']?.toString(),
      serviceProviderId: data['serviceProviderId']?.toString(),
      sellerUserId: data['sellerUserId']?.toString(),
      merchantId: data['merchantId']?.toString(),
      merchantName: data['merchantName']?.toString(),
      serviceType: data['serviceType']?.toString() ?? 'marketplace',
      createdAt: createdAt,
    );
  }

  /// Firebase-backed photo search.
  ///
  /// Marketplace content now lives in Firestore, so this method no longer calls
  /// `/marketplace/search/photo/url`.
  ///
  /// Current behavior:
  /// - load active items from `marketplace_items` (cache first, then server)
  /// - compute a visual hash from query image bytes
  /// - compare against stored (or lazily derived) item image hashes
  /// - rank by visual similarity first, then keyword overlap/newness
  Future<List<MarketplaceDetailModel>> searchByPhotoBytes(
    Uint8List bytes, {
    String filename = 'photo.jpg',
  }) async {
    try {
      if (bytes.isEmpty) return [];
      if (filename.trim().isEmpty) filename = 'photo.jpg';
      final queryHash = await computeVisualHash(bytes);

      QuerySnapshot? snapshot;

      // cache first for instant UX/offline support
      try {
        snapshot = await _firestore
            .collection('marketplace_items')
            .orderBy('createdAt', descending: true)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {}

      // server fallback
      snapshot ??= await _firestore
          .collection('marketplace_items')
          .orderBy('createdAt', descending: true)
          .get(const GetOptions(source: Source.server));

      final nameTokens = _tokenize(filename);
      final keywordTokens = <String>{
        ...nameTokens,
        ..._categoryHintsFromTokens(nameTokens),
      };

      final scored = <({
        MarketplaceDetailModel item,
        int visualDistance,
        int keywordScore,
        int ts,
        String docId,
        Set<String> hashes,
      })>[];
      final missingHash = <({String docId, MarketplaceDetailModel item})>[];

      for (final doc in snapshot.docs) {
        final item = _fromFirestoreDoc(doc);
        final hasImage = item.image.trim().isNotEmpty || item.gallery.isNotEmpty;
        if (!hasImage) continue;

        final data = (doc.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
        final hashes = _extractVisualHashes(data);
        if (hashes.isEmpty) {
          missingHash.add((docId: doc.id, item: item));
        }

        final searchable = [
          item.name,
          item.category,
          item.description,
          item.location,
          item.image,
          ...item.gallery,
        ].join(' ').toLowerCase();

        int score = 0;
        for (final t in keywordTokens) {
          if (t.isEmpty) continue;
          if (searchable.contains(t)) score += 3;
        }

        int visualDistance = _noVisualDistance;
        if (queryHash != null && hashes.isNotEmpty) {
          for (final h in hashes) {
            final d = _hammingDistance64Hex(queryHash, h);
            if (d < visualDistance) visualDistance = d;
          }
        }

        final ts = item.createdAt?.millisecondsSinceEpoch ?? 0;
        scored.add((
          item: item,
          visualDistance: visualDistance,
          keywordScore: score,
          ts: ts,
          docId: doc.id,
          hashes: hashes,
        ));
      }

      // Fast path first: return using existing stored hashes (no network image fetches).
      // If no useful visual matches, derive only a small capped subset.
      final hasVisualFromStored =
          scored.any((e) => e.visualDistance != _noVisualDistance);
      if (!hasVisualFromStored && queryHash != null && missingHash.isNotEmpty) {
        final toDerive = missingHash.take(_deriveLimitPerSearch).toList();
        for (final entry in toDerive) {
          final derived = await _deriveVisualHashFromItem(entry.item)
              .timeout(_deriveTimeout, onTimeout: () => null);
          if (derived == null) continue;

          final idx = scored.indexWhere((e) => e.docId == entry.docId);
          if (idx >= 0) {
            final current = scored[idx];
            final newHashes = {...current.hashes, derived};
            int best = _noVisualDistance;
            for (final h in newHashes) {
              final d = _hammingDistance64Hex(queryHash, h);
              if (d < best) best = d;
            }
            scored[idx] = (
              item: current.item,
              visualDistance: best,
              keywordScore: current.keywordScore,
              ts: current.ts,
              docId: current.docId,
              hashes: newHashes,
            );
          }

          // Best-effort: backfill for future fast/accurate matches.
          unawaited(_firestore.collection('marketplace_items').doc(entry.docId).set({
            'imageHash': derived,
            'imageHashes': FieldValue.arrayUnion([derived]),
          }, SetOptions(merge: true)));
        }
      }

      scored.sort((a, b) {
        final aHasVisual = a.visualDistance != _noVisualDistance;
        final bHasVisual = b.visualDistance != _noVisualDistance;
        if (aHasVisual != bHasVisual) return aHasVisual ? -1 : 1;
        if (aHasVisual && bHasVisual) {
          final byVisual = a.visualDistance.compareTo(b.visualDistance);
          if (byVisual != 0) return byVisual;
        }
        final byKeyword = b.keywordScore.compareTo(a.keywordScore);
        if (byKeyword != 0) return byKeyword;
        return b.ts.compareTo(a.ts);
      });
      if (queryHash != null) {
        // Prefer confident visual matches first.
        final strong = scored
            .where((e) => e.visualDistance <= _strongVisualThreshold)
            .map((e) => e.item)
            .take(_maxPhotoResults)
            .toList();
        if (strong.isNotEmpty) return strong;

        // Then allow slightly looser visual matches before falling back.
        final soft = scored
            .where((e) => e.visualDistance <= _softVisualThreshold)
            .map((e) => e.item)
            .toList();
        if (soft.isNotEmpty) return soft.take(_maxPhotoResults).toList();
      }

      final fallback = scored.map((e) => e.item).take(_maxPhotoResults).toList();
      return fallback;
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('searchByPhoto ApiException: ${e.message}');
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('searchByPhoto error: $e');
      rethrow;
    }
  }


  /// Public so create/update flows can persist robust visual hashes on write.
  Future<String?> computeVisualHash(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 9,
        targetHeight: 8,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final p = data.buffer.asUint8List();
      if (p.length < 9 * 8 * 4) return null;

      int bitIndex = 0;
      BigInt hash = BigInt.zero;
      for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
          final left = ((y * 9) + x) * 4;
          final right = ((y * 9) + x + 1) * 4;
          final l = _lumaFromRgba(p, left);
          final r = _lumaFromRgba(p, right);
          if (l > r) {
            hash |= (BigInt.one << bitIndex);
          }
          bitIndex++;
        }
      }
      return hash.toRadixString(16).padLeft(16, '0');
    } catch (e) {
      if (kDebugMode) debugPrint('computeVisualHash error: $e');
      return null;
    }
  }

  int _lumaFromRgba(Uint8List rgba, int i) {
    final r = rgba[i];
    final g = rgba[i + 1];
    final b = rgba[i + 2];
    return ((299 * r + 587 * g + 114 * b) ~/ 1000);
  }

  int _hammingDistance64Hex(String aHex, String bHex) {
    try {
      final a = BigInt.parse(aHex, radix: 16);
      final b = BigInt.parse(bHex, radix: 16);
      var x = a ^ b;
      int count = 0;
      while (x > BigInt.zero) {
        x &= (x - BigInt.one);
        count++;
      }
      return count;
    } catch (_) {
      return 999;
    }
  }

  Set<String> _extractVisualHashes(Map<String, dynamic> data) {
    final out = <String>{};

    void addIfValid(dynamic v) {
      final s = (v ?? '').toString().trim().toLowerCase();
      if (RegExp(r'^[0-9a-f]{16}$').hasMatch(s)) out.add(s);
    }

    addIfValid(data['imageHash']);
    addIfValid(data['photoHash']);
    final imageHashes = data['imageHashes'];
    if (imageHashes is List) {
      for (final h in imageHashes) {
        addIfValid(h);
      }
    }
    final galleryHashes = data['galleryHashes'];
    if (galleryHashes is List) {
      for (final h in galleryHashes) {
        addIfValid(h);
      }
    }
    return out;
  }

  Future<String?> _deriveVisualHashFromItem(MarketplaceDetailModel item) async {
    final candidates = <String>[
      item.image.trim(),
      ...item.gallery.map((e) => e.trim()),
    ].where((u) => u.isNotEmpty).toList();

    for (final raw in candidates) {
      try {
        final cached = _derivedHashMemo[raw];
        if (cached != null && cached.isNotEmpty) return cached;
        final url = await _resolveImageUrl(raw);
        if (url == null) continue;
        final res = await http.get(url).timeout(const Duration(seconds: 8));
        if (res.statusCode < 200 || res.statusCode >= 300 || res.bodyBytes.isEmpty) {
          continue;
        }
        final h = await computeVisualHash(res.bodyBytes);
        if (h != null) {
          _derivedHashMemo[raw] = h;
          return h;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<Uri?> _resolveImageUrl(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return Uri.tryParse(s);
    }
    try {
      if (s.startsWith('gs://')) {
        final u = await _storage.refFromURL(s).getDownloadURL();
        return Uri.tryParse(u);
      }
      if (!s.startsWith('data:')) {
        final u = await _storage.ref(s).getDownloadURL();
        return Uri.tryParse(u);
      }
    } catch (_) {}
    return null;
  }

  Set<String> _tokenize(String raw) {
    final cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp(r'\.[a-z0-9]{2,5}$'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    if (cleaned.isEmpty) return {};
    return cleaned
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3 && t != 'photo' && t != 'img' && t != 'image')
        .toSet();
  }

  Set<String> _categoryHintsFromTokens(Set<String> tokens) {
    final hints = <String>{};
    bool any(List<String> checks) => checks.any(tokens.contains);

    if (any(['phone', 'iphone', 'android', 'samsung', 'tecno', 'infinix'])) {
      hints.addAll(['phone', 'mobile', 'electronics']);
    }
    if (any(['laptop', 'macbook', 'hp', 'dell', 'lenovo'])) {
      hints.addAll(['laptop', 'computer', 'electronics']);
    }
    if (any(['shoe', 'sneaker', 'heel', 'boot'])) {
      hints.addAll(['shoe', 'fashion', 'clothing']);
    }
    if (any(['dress', 'shirt', 'trouser', 'jean'])) {
      hints.addAll(['fashion', 'clothing']);
    }
    if (any(['fridge', 'tv', 'microwave', 'sofa', 'table'])) {
      hints.addAll(['home', 'appliance', 'furniture']);
    }

    return hints;
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

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:vero360_app/models/Latest_model.dart';
import 'package:vero360_app/config/api_config.dart';

class LatestArrivalsServicess {
  // ---------------- URL builder (adds /vero) ----------------

  Future<String> _apiBase() async {
    final base =
        await ApiConfig.readBase(); // e.g. https://heflexitservice.co.za
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;

    final p = ApiConfig.apiPrefix.trim(); // e.g. /vero
    if (p.isEmpty) return root;

    final prefix = p.startsWith('/') ? p : '/$p';

    // avoid double prefix if someone saved base already containing /vero
    if (root.endsWith(prefix)) return root;

    return '$root$prefix';
  }

  Uri _u(String path, String base) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  // ---------------- decode & compact errors ----------------

  String _compactBody(String body) {
    final t = body.trim();
    if (t.isEmpty) return '';
    final lower = t.toLowerCase();
    if (lower.contains('<html') || lower.contains('<!doctype')) {
      final title = RegExp(r'<title>(.*?)</title>', caseSensitive: false)
          .firstMatch(t)
          ?.group(1);
      return title != null && title.trim().isNotEmpty
          ? title.trim()
          : 'HTML error response';
    }
    if (t.length > 350) return '${t.substring(0, 350)}...';
    return t;
  }

  dynamic _decode(http.Response r, {required String where}) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(
          'HTTP ${r.statusCode} at $where: ${_compactBody(r.body)}');
    }
    if (r.body.isEmpty) return {};
    return json.decode(r.body);
  }

  Map<String, String> _jsonHeaders() => const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // ---------------- upload (NO AUTH multipart) ----------------

  Future<String> uploadImageBytes(
    Uint8List bytes, {
    String filename = 'latest.jpg',
    String mime = 'image/jpeg',
  }) async {
    final base = await _apiBase();
    final uri = _u('/uploads', base);

    final req = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json';

    final parts = mime.split('/');
    final mediaType = (parts.length == 2)
        ? MediaType(parts[0], parts[1])
        : MediaType('image', 'jpeg');

    // if your backend expects 'image' instead of 'file', change this field name
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: mediaType,
    ));

    final resp = await http.Response.fromStream(await req.send());
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'Upload failed: HTTP ${resp.statusCode} ${_compactBody(resp.body)}',
      );
    }

    final decoded = json.decode(resp.body);
    final url = decoded is Map ? decoded['url']?.toString() : null;

    if (url == null || url.trim().isEmpty) {
      throw Exception('Upload ok but no "url" returned');
    }
    return url.trim();
  }

  // ---------------- list (public) ----------------

  Future<List<LatestArrivalModel>> fetchAll() async {
    final base = await _apiBase();
    final url = _u('/latestarrivals', base);

    final r =
        await http.get(url, headers: const {'Accept': 'application/json'});
    final body = _decode(r, where: 'GET $url');

    final list =
        body is List ? body : (body is Map ? (body['data'] ?? []) : []);
    return (list as List).map((e) => LatestArrivalModel.fromJson(e)).toList();
  }

  // ---------------- list mine (NO AUTH) ----------------
  // If your backend does NOT have /me public, then change to fetchAll()
  // or create a public route for "mine".
  Future<List<LatestArrivalModel>> fetchMine() async {
    final base = await _apiBase();
    final url = _u('/latestarrivals/me', base);

    final r =
        await http.get(url, headers: const {'Accept': 'application/json'});
    final body = _decode(r, where: 'GET $url');

    final list =
        body is List ? body : (body is Map ? (body['data'] ?? []) : []);
    return (list as List).map((e) => LatestArrivalModel.fromJson(e)).toList();
  }

  // ---------------- create/update/delete (NO AUTH) ----------------

  Future<void> create(LatestArrivalModel item) async {
    final base = await _apiBase();
    final url = _u('/latestarrivals', base);

    final r = await http.post(
      url,
      headers: _jsonHeaders(),
      body: json.encode(item.toJson()),
    );
    _decode(r, where: 'POST $url');
  }

  Future<void> update(int id, Map<String, dynamic> patch) async {
    final base = await _apiBase();
    final url = _u('/latestarrivals/$id', base);

    final r = await http.put(
      url,
      headers: _jsonHeaders(),
      body: json.encode(patch),
    );
    _decode(r, where: 'PUT $url');
  }

  Future<void> delete(int id) async {
    final base = await _apiBase();
    final url = _u('/latestarrivals/$id', base);

    final r =
        await http.delete(url, headers: const {'Accept': 'application/json'});
    _decode(r, where: 'DELETE $url');
  }
}

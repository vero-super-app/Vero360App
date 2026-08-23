import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:vero360_app/GeneralModels/tender.models.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class TendersService {
  const TendersService();

  /// Active tenders from Vero360 web: `GET /api/tenders`.
  Future<List<TenderPost>> fetchTenders({int limit = 100}) async {
    final uri = ApiConfig.siteEndpoint('/api/tenders').replace(
      queryParameters: {'limit': '$limit'},
    );

    late final http.Response res;
    try {
      res = await http
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'Vero360App/1.0',
            },
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException(
        message: 'Could not reach tenders. Check your connection and try again.',
      );
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        message: 'Failed to load tenders (${res.statusCode}).',
      );
    }

    try {
      final decoded = jsonDecode(res.body);
      final List<dynamic> list;
      if (decoded is Map && decoded['items'] is List) {
        list = decoded['items'] as List;
      } else if (decoded is List) {
        list = decoded;
      } else {
        throw const ApiException(message: 'Unexpected tenders response.');
      }

      final out = <TenderPost>[];
      for (final e in list) {
        if (e is! Map) continue;
        try {
          final t = TenderPost.fromJson(Map<String, dynamic>.from(e));
          if (t.id.isEmpty || t.title.isEmpty || t.tenderUrl.isEmpty) continue;
          out.add(t);
        } catch (_) {
          // Skip malformed rows.
        }
      }
      return out;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        message: 'Failed to parse tenders. Please try again.',
      );
    }
  }
}

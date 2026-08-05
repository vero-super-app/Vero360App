// lib/services/jobs_service.dart

import 'dart:convert';

import 'package:vero360_app/GeneralModels/job.models.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class JobsService {
  const JobsService();

  /// Fetch job posts. Matches backend `GET /jobs?activeOnly=&region=`.
  /// [region] — `malawi` | `international` (omit for all active jobs).
  Future<List<JobPost>> fetchJobs({
    bool activeOnly = true,
    JobRegion? region,
  }) async {
    const path = 'jobs';

    final query = <String, String>{
      'activeOnly': activeOnly ? 'true' : 'false',
      if (region != null) 'region': region.name,
    };

    final res = await ApiClient.get(
      path,
      queryParameters: query,
    );

    try {
      final decoded = jsonDecode(res.body);
      final List<dynamic> list;
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map && decoded['data'] is List) {
        list = decoded['data'] as List;
      } else {
        throw const ApiException(
          message: 'Unexpected response from server.',
        );
      }

      final out = <JobPost>[];
      for (final e in list) {
        if (e is! Map) continue;
        try {
          final job = JobPost.fromJson(Map<String, dynamic>.from(e));
          if (job.id <= 0 || job.position.trim().isEmpty) continue;
          out.add(job);
        } catch (_) {
          // Skip malformed rows so one bad sync item doesn't blank Jobs.
        }
      }
      return out;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        message: 'Failed to parse jobs list. Please try again.',
      );
    }
  }
}

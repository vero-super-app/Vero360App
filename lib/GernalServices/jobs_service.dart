// lib/services/jobs_service.dart

import 'dart:convert';

import 'package:vero360_app/GeneralModels/job.models.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class JobsService {
  const JobsService();

  /// Fetch job posts. activeOnly=true means only active jobs (default).
  Future<List<JobPost>> fetchJobs({bool activeOnly = true}) async {
    final queryValue = activeOnly ? 'true' : 'false';
    const path = 'jobs';

    final res = await ApiClient.get(
      path,
      queryParameters: {'activeOnly': queryValue},
    );

    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw const ApiException(
          message: 'Unexpected response from server.',
        );
      }

      return decoded
          .map((e) => JobPost.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw const ApiException(
        message: 'Failed to parse jobs list. Please try again.',
      );
    }
  }
}

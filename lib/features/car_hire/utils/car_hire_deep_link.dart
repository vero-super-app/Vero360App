import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_detail_page.dart';

/// A parsed car-hire deep link.
///
/// Supported forms (all additive, so old shared links keep working):
///   vero360://car-hire/123?startAt=...&endAt=...
///   vero360://car-hire?id=123
///   https://vero360.app/car-hire/123
///
/// Dates are optional. When present they are converted to local time so the
/// picker on the detail page shows the same wall-clock range the renter chose
/// on the web.
class CarHireDeepLinkTarget {
  const CarHireDeepLinkTarget({
    required this.carId,
    this.startAt,
    this.endAt,
  });

  final int carId;
  final DateTime? startAt;
  final DateTime? endAt;
}

bool isCarHireDeepLinkUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();

  if (scheme == 'vero360') {
    return host == 'car-hire' ||
        host == 'carhire' ||
        host == 'car-rental' ||
        host == 'carrental';
  }

  if (scheme == 'https' || scheme == 'http') {
    if (host != 'vero360.app' && host != 'www.vero360.app') return false;
    return _carHireIdFromPathSegments(uri.pathSegments) != null;
  }

  return false;
}

CarHireDeepLinkTarget? carHireTargetFromUri(Uri uri) {
  if (!isCarHireDeepLinkUri(uri)) return null;

  int? id;
  if (uri.scheme.toLowerCase() == 'vero360') {
    id = _positiveInt(uri.queryParameters['id']);
    // vero360://car-hire/123 puts "car-hire" in the host and "123" in the path.
    id ??= _firstPositiveInt(uri.pathSegments);
    id ??= _carHireIdFromPathSegments(uri.pathSegments);
  } else {
    id = _carHireIdFromPathSegments(uri.pathSegments);
  }

  if (id == null || id <= 0) return null;

  final start = _parseLocalDate(
    uri.queryParameters['startAt'] ?? uri.queryParameters['start'],
  );
  final end = _parseLocalDate(
    uri.queryParameters['endAt'] ?? uri.queryParameters['end'],
  );

  return CarHireDeepLinkTarget(
    carId: id,
    startAt: start,
    endAt: end != null && start != null && !end.isAfter(start) ? null : end,
  );
}

/// Pushes the renter detail page when the navigator is ready.
bool openCarHireDeepLink(Uri uri, GlobalKey<NavigatorState> navigatorKey) {
  final target = carHireTargetFromUri(uri);
  if (target == null) return false;

  final navigator = navigatorKey.currentState;
  if (navigator == null) return false;

  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => CarHireDetailPage(
        carId: target.carId,
        initialStartAt: target.startAt,
        initialEndAt: target.endAt,
      ),
    ),
  );
  return true;
}

int? _carHireIdFromPathSegments(List<String> segments) {
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i].toLowerCase();
    if (segment == 'car-hire' ||
        segment == 'carhire' ||
        segment == 'car-rental' ||
        segment == 'carrental') {
      for (var j = i + 1; j < segments.length; j++) {
        final id = _positiveInt(segments[j]);
        if (id != null) return id;
      }
    }
  }
  return null;
}

int? _firstPositiveInt(List<String> segments) {
  for (final segment in segments) {
    final id = _positiveInt(segment);
    if (id != null) return id;
  }
  return null;
}

int? _positiveInt(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

DateTime? _parseLocalDate(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  return parsed?.toLocal();
}

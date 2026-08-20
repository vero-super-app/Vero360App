import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Shared marketplace date helpers (posted badges / sorting).
class MarketplaceTime {
  MarketplaceTime._();

  /// Accepts Firestore [Timestamp], [DateTime], ISO strings, and epoch millis/seconds.
  static DateTime? parseCreatedAt(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is num) {
      final n = raw.toInt();
      // Seconds vs millis (seconds around year 2001..2286 fit in 10 digits).
      if (n > 1000000000 && n < 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true)
            .toLocal();
      }
      if (n > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toLocal();
      }
      return null;
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final asInt = int.tryParse(s);
    if (asInt != null) return parseCreatedAt(asInt);
    return DateTime.tryParse(s)?.toLocal();
  }

  /// Full calendar months between [from] and [to] (can be 0, 5, 12, …).
  static int calendarMonthsBetween(DateTime from, DateTime to) {
    var months = (to.year - from.year) * 12 + (to.month - from.month);
    if (to.day < from.day) months -= 1;
    return months < 0 ? 0 : months;
  }

  /// Relative label from real wall-clock time.
  /// Supports minutes → hours → days → weeks → months (incl. 5mo) → years.
  static String formatTimeAgo(DateTime time, {bool verbose = false}) {
    final local = time.isUtc ? time.toLocal() : time;
    final now = DateTime.now();
    final diff = now.difference(local);

    if (diff.isNegative || diff.inSeconds < 60) {
      return 'Just now';
    }
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return verbose
          ? '$m ${m == 1 ? 'min' : 'mins'} ago'
          : '${m}m ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return verbose ? '$h ${h == 1 ? 'hr' : 'hrs'} ago' : '${h}h ago';
    }
    if (diff.inDays < 7) {
      final d = diff.inDays;
      return verbose ? '$d ${d == 1 ? 'day' : 'days'} ago' : '${d}d ago';
    }

    final months = calendarMonthsBetween(local, now);

    // Under ~1 calendar month → weeks
    if (months < 1) {
      final weeks = (diff.inDays / 7).floor().clamp(1, 4);
      return verbose
          ? '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago'
          : '${weeks}w ago';
    }

    // 1–11 months (e.g. 5 months ago)
    if (months < 12) {
      return verbose
          ? '$months ${months == 1 ? 'month' : 'months'} ago'
          : '${months}mo ago';
    }

    // 1+ years
    final years = (months / 12).floor().clamp(1, 999);
    return verbose
        ? '$years ${years == 1 ? 'year' : 'years'} ago'
        : '${years}y ago';
  }
}

/// Shop open/closed helpers shared by merchant dashboard + buyer pages.
///
/// Tolerates legacy separators (`-`, en/em dash, and corrupted `G??` saves).
class MarketplaceShopHours {
  MarketplaceShopHours._();

  static final RegExp _timeRe = RegExp(r'(\d{1,2}):(\d{2})');

  static String formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Canonical string stored in Firestore / prefs: `08:00-17:00`.
  static String formatRange(TimeOfDay open, TimeOfDay close) =>
      '${formatTime(open)}-${formatTime(close)}';

  /// Pretty label for UI: `08:00–17:00`.
  static String formatRangeDisplay(TimeOfDay open, TimeOfDay close) =>
      '${formatTime(open)}–${formatTime(close)}';

  static TimeOfDay? parseTime(String raw) {
    final m = _timeRe.firstMatch(raw.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return TimeOfDay(hour: h, minute: min);
  }

  /// Extracts open/close from any `HH:MM … HH:MM` string.
  static ({TimeOfDay open, TimeOfDay close})? parseRange(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    final matches = _timeRe.allMatches(s).toList();
    if (matches.length < 2) return null;
    final open = parseTime(matches[0].group(0)!);
    final close = parseTime(matches[1].group(0)!);
    if (open == null || close == null) return null;
    return (open: open, close: close);
  }

  /// Normalize legacy / corrupted ranges to `HH:MM-HH:MM`.
  static String? normalize(String? raw) {
    final pair = parseRange(raw);
    if (pair == null) return null;
    return formatRange(pair.open, pair.close);
  }

  static List<int> parseDays(dynamic raw) {
    final next = <int>{};
    if (raw is List) {
      for (final e in raw) {
        final n = e is int ? e : int.tryParse('$e');
        if (n != null && n >= 1 && n <= 7) next.add(n);
      }
    } else if (raw is String && raw.trim().isNotEmpty) {
      for (final part in raw.split(RegExp(r'[,;\s]+'))) {
        final n = int.tryParse(part.trim());
        if (n != null && n >= 1 && n <= 7) next.add(n);
      }
    }
    return (next.toList()..sort());
  }

  /// True when [now] falls inside today's open window.
  /// Empty [openingDays] means every day.
  static bool isOpenNow(
    String? openingHours, [
    List<int> openingDays = const [],
    DateTime? now,
  ]) {
    final pair = parseRange(openingHours);
    if (pair == null) return false;
    final clock = now ?? DateTime.now();
    if (openingDays.isNotEmpty && !openingDays.contains(clock.weekday)) {
      return false;
    }
    final nowM = clock.hour * 60 + clock.minute;
    final openM = pair.open.hour * 60 + pair.open.minute;
    final closeM = pair.close.hour * 60 + pair.close.minute;
    if (openM == closeM) return false;
    if (openM < closeM) {
      return nowM >= openM && nowM < closeM;
    }
    // Overnight window (e.g. 18:00-02:00).
    return nowM >= openM || nowM < closeM;
  }
}

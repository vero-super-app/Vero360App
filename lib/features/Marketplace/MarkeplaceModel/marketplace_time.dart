import 'package:cloud_firestore/cloud_firestore.dart';

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

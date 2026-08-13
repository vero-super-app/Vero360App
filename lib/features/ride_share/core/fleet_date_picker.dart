import 'package:flutter/material.dart';

/// Calendar day only (avoids time-of-day breaking [showDatePicker] bounds).
DateTime fleetDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? tryParseFleetDate(dynamic raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  if (text.isEmpty) return null;
  // Prefer the calendar yyyy-MM-dd prefix so UTC midnight does not shift the day.
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  if (match != null) {
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return fleetDateOnly(parsed);
}

/// Date-only `yyyy-MM-dd` for API payloads (avoids TZ day-shifts).
String fleetDateIso(DateTime d) {
  final day = fleetDateOnly(d);
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final dd = day.day.toString().padLeft(2, '0');
  return '$y-$m-$dd';
}

/// [showDatePicker] that always clamps [initialDate] into [firstDate, lastDate].
///
/// Flutter asserts and silently fails when a stored/placeholder date (often
/// "today" from backend defaults, or an expired licence) sits outside the
/// allowed range.
Future<DateTime?> showFleetDatePicker(
  BuildContext context, {
  DateTime? current,
  required DateTime firstDate,
  required DateTime lastDate,
}) async {
  final first = fleetDateOnly(firstDate);
  var last = fleetDateOnly(lastDate);
  if (last.isBefore(first)) last = first;

  var initial = fleetDateOnly(current ?? DateTime.now());
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;

  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
  );
  return picked == null ? null : fleetDateOnly(picked);
}

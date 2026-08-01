import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

final Map<String, Future<String>> _accDlUrlCache = {};

bool accListingIsHttp(String s) =>
    s.startsWith('http://') || s.startsWith('https://');

bool _accIsGs(String s) => s.startsWith('gs://');

bool accListingLooksLikeBase64(String s) {
  final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
  if (x.length < 150) return false;
  return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
}

Future<String?> accListingToFirebaseDownloadUrl(String raw) async {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (accListingIsHttp(s)) return s;

  if (_accDlUrlCache.containsKey(s)) {
    try {
      return await _accDlUrlCache[s]!;
    } catch (_) {
      return null;
    }
  }

  Future<String> fut() async {
    if (_accIsGs(s)) {
      return FirebaseStorage.instance.refFromURL(s).getDownloadURL();
    }
    return FirebaseStorage.instance.ref(s).getDownloadURL();
  }

  _accDlUrlCache[s] = fut();
  try {
    return await _accDlUrlCache[s]!;
  } catch (_) {
    return null;
  }
}

/// Cover + gallery strings: http(s), gs://, storage path, or base64.
Widget accImageFromAnySource(
  String raw, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
  BorderRadius? radius,
}) {
  final s = raw.trim();

  Widget wrap(Widget child) {
    if (radius == null) return child;
    return ClipRRect(borderRadius: radius, child: child);
  }

  if (s.isEmpty) {
    return wrap(Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_rounded),
    ));
  }

  if (accListingLooksLikeBase64(s)) {
    try {
      final base64Part = s.contains(',') ? s.split(',').last : s;
      final bytes = base64Decode(base64Part);
      return wrap(Image.memory(bytes, fit: fit, width: width, height: height));
    } catch (_) {}
  }

  if (accListingIsHttp(s)) {
    return wrap(Image.network(
      s,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_rounded),
      ),
      loadingBuilder: (c, child, progress) {
        if (progress == null) return child;
        return Container(
          width: width,
          height: height,
          color: Colors.grey.shade100,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      },
    ));
  }

  return FutureBuilder<String?>(
    future: accListingToFirebaseDownloadUrl(s),
    builder: (context, snap) {
      final url = snap.data;
      if (url == null || url.isEmpty) {
        return wrap(Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported_rounded),
        ));
      }
      return wrap(Image.network(
        url,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported_rounded),
        ),
      ));
    },
  );
}

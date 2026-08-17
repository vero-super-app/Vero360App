/// Public + in-app share URLs for food menu items.
String foodProductShareId({
  int? sqlId,
  String? firestoreListingId,
}) {
  if (sqlId != null && sqlId > 0) return '$sqlId';
  final doc = (firestoreListingId ?? '').trim();
  if (doc.isNotEmpty) return doc;
  return '';
}

String? foodShareImageUrl(String? primary, [List<String>? gallery]) {
  final p = (primary ?? '').trim();
  if (p.startsWith('http://') || p.startsWith('https://')) return p;
  for (final raw in gallery ?? const <String>[]) {
    final g = raw.trim();
    if (g.startsWith('http://') || g.startsWith('https://')) return g;
  }
  return null;
}

String foodShareUrl({
  required String id,
  String? name,
  String? restaurant,
  String? price,
  String? image,
  String? description,
  String? location,
}) {
  final params = <String, String>{};
  final n = name?.trim() ?? '';
  final r = restaurant?.trim() ?? '';
  final p = price?.trim() ?? '';
  final img = image?.trim() ?? '';
  final loc = location?.trim() ?? '';
  final desc = description?.trim() ?? '';
  final q = [n, r, loc].where((s) => s.isNotEmpty).join(' ');
  if (q.isNotEmpty) params['q'] = q;
  if (n.isNotEmpty) params['name'] = n;
  if (r.isNotEmpty) params['merchant'] = r;
  if (loc.isNotEmpty) params['loc'] = loc;
  if (p.isNotEmpty) params['price'] = p;
  if (desc.isNotEmpty) {
    params['desc'] = desc.length > 500 ? desc.substring(0, 500) : desc;
  }
  if (img.startsWith('http://') || img.startsWith('https://')) {
    params['img'] = img;
  }
  final pathId = id.trim();
  return Uri(
    scheme: 'https',
    host: 'vero360.app',
    path: pathId.isNotEmpty ? '/food/$pathId' : '/food',
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}

bool _isVeroHost(String host) =>
    host == 'vero360.app' || host == 'www.vero360.app';

String? foodIdFromShareUri(Uri uri) {
  final host = uri.host.toLowerCase();
  final segs = uri.pathSegments
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (uri.scheme == 'vero360' && host == 'food') {
    return segs.isEmpty ? null : segs.first;
  }
  if (_isVeroHost(host) &&
      segs.length >= 2 &&
      segs.first.toLowerCase() == 'food') {
    return segs[1];
  }
  return null;
}

bool isFoodShareUri(Uri uri) => foodIdFromShareUri(uri) != null;

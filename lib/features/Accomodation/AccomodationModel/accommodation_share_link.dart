/// Public + in-app share URLs for a stay, same pattern as marketplace items.
String accommodationShareUrl({
  required int id,
  String? name,
  String? location,
  String? price,
  String? image,
  String? period,
}) {
  final q = [
    name?.trim(),
    location?.trim(),
  ].where((s) => s != null && s.isNotEmpty).join(' ');
  final params = <String, String>{};
  if (q.isNotEmpty) params['q'] = q;
  final n = name?.trim() ?? '';
  final loc = location?.trim() ?? '';
  final p = price?.trim() ?? '';
  final img = image?.trim() ?? '';
  final per = period?.trim() ?? '';
  if (n.isNotEmpty) params['name'] = n;
  if (loc.isNotEmpty) params['loc'] = loc;
  if (p.isNotEmpty) params['price'] = p;
  if (per.isNotEmpty) params['period'] = per;
  if (img.startsWith('http://') || img.startsWith('https://')) {
    params['img'] = img;
  }
  return Uri(
    scheme: 'https',
    host: 'vero360.app',
    path: id > 0 ? '/accommodation/$id' : '/accommodation',
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}

int? accommodationIdFromShareUri(Uri uri) {
  final host = uri.host.toLowerCase();
  final segs = uri.pathSegments
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  if (uri.scheme == 'vero360' &&
      (host == 'accommodation' || host == 'stay' || host == 'stays')) {
    if (segs.isEmpty) return null;
    return int.tryParse(segs.first);
  }

  final isVeroHost = host == 'vero360.app' || host == 'www.vero360.app';
  if (!isVeroHost && uri.scheme != 'https' && uri.scheme != 'http') {
    return null;
  }
  if (isVeroHost &&
      segs.length >= 2 &&
      (segs.first == 'accommodation' ||
          segs.first == 'stay' ||
          segs.first == 'stays')) {
    return int.tryParse(segs[1]);
  }
  return null;
}

String? accommodationSearchQueryFromShareUri(Uri uri) {
  final q = (uri.queryParameters['q'] ??
          uri.queryParameters['search'] ??
          uri.queryParameters['name'] ??
          '')
      .trim();
  return q.isEmpty ? null : q;
}

bool isAccommodationShareUri(Uri uri) {
  if (accommodationIdFromShareUri(uri) != null) return true;
  final host = uri.host.toLowerCase();
  final segs = uri.pathSegments.map((s) => s.toLowerCase()).toList();
  if (uri.scheme == 'vero360' &&
      (host == 'accommodation' || host == 'stay' || host == 'stays')) {
    return true;
  }
  if ((host == 'vero360.app' || host == 'www.vero360.app') &&
      segs.isNotEmpty &&
      (segs.first == 'accommodation' ||
          segs.first == 'stay' ||
          segs.first == 'stays')) {
    return true;
  }
  return false;
}

/// Public + in-app share URLs for marketplace products and merchant shops.

String marketplaceProductShareId({
  int? sqlItemId,
  String? firestoreDocId,
}) {
  if (sqlItemId != null && sqlItemId > 0) return '$sqlItemId';
  final doc = (firestoreDocId ?? '').trim();
  if (doc.isNotEmpty) return doc;
  return '';
}

String? marketplaceShareImageUrl(String? primary, [List<String>? gallery]) {
  final p = (primary ?? '').trim();
  if (p.startsWith('http://') || p.startsWith('https://')) return p;
  for (final raw in gallery ?? const <String>[]) {
    final g = raw.trim();
    if (g.startsWith('http://') || g.startsWith('https://')) return g;
  }
  return null;
}

String marketplaceProductShareUrl({
  required String id,
  String? name,
  String? location,
  String? price,
  String? image,
  String? description,
  String? merchant,
}) {
  final params = <String, String>{};
  final n = name?.trim() ?? '';
  final loc = location?.trim() ?? '';
  final p = price?.trim() ?? '';
  final img = image?.trim() ?? '';
  final m = merchant?.trim() ?? '';
  final desc = description?.trim() ?? '';
  final q = [n, loc].where((s) => s.isNotEmpty).join(' ');
  if (q.isNotEmpty) params['q'] = q;
  if (n.isNotEmpty) params['name'] = n;
  if (loc.isNotEmpty) params['loc'] = loc;
  if (p.isNotEmpty) params['price'] = p;
  if (m.isNotEmpty) params['merchant'] = m;
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
    path: pathId.isNotEmpty ? '/marketplace/$pathId' : '/marketplace',
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}

String marketplaceShopShareUrl({
  required String merchantId,
  String? name,
  String? image,
}) {
  final params = <String, String>{};
  final n = name?.trim() ?? '';
  final img = image?.trim() ?? '';
  if (n.isNotEmpty) params['name'] = n;
  if (img.startsWith('http://') || img.startsWith('https://')) {
    params['img'] = img;
  }
  final id = merchantId.trim();
  return Uri(
    scheme: 'https',
    host: 'vero360.app',
    path: id.isNotEmpty ? '/shop/$id' : '/shop',
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}

bool _isVeroHost(String host) =>
    host == 'vero360.app' || host == 'www.vero360.app';

List<String> _segs(Uri uri) => uri.pathSegments
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

String? marketplaceProductIdFromShareUri(Uri uri) {
  final host = uri.host.toLowerCase();
  final segs = _segs(uri);
  if (uri.scheme == 'vero360' && host == 'marketplace') {
    return segs.isEmpty ? null : segs.first;
  }
  if (_isVeroHost(host) &&
      segs.length >= 2 &&
      segs.first.toLowerCase() == 'marketplace' &&
      segs[1].toLowerCase() != 'shop') {
    return segs[1];
  }
  return null;
}

String? marketplaceShopIdFromShareUri(Uri uri) {
  final host = uri.host.toLowerCase();
  final segs = _segs(uri);
  if (uri.scheme == 'vero360' && (host == 'shop' || host == 'merchant')) {
    return segs.isEmpty ? null : segs.first;
  }
  if (_isVeroHost(host) && segs.length >= 2) {
    final first = segs.first.toLowerCase();
    if (first == 'shop' || first == 'merchant') return segs[1];
  }
  return null;
}

String? marketplaceSearchQueryFromShareUri(Uri uri) {
  final q = (uri.queryParameters['q'] ??
          uri.queryParameters['search'] ??
          uri.queryParameters['name'] ??
          '')
      .trim();
  return q.isEmpty ? null : q;
}

bool isMarketplaceProductShareUri(Uri uri) =>
    marketplaceProductIdFromShareUri(uri) != null;

bool isMarketplaceShopShareUri(Uri uri) =>
    marketplaceShopIdFromShareUri(uri) != null;

/// Client-side text moderation for marketplace listings.
/// Server Cloud Functions re-check the same categories; this is a fast pre-gate.

class MarketplaceModeration {
  MarketplaceModeration._();

  /// Normalized blocklist (EN + common slang). Keep in sync with
  /// `functions/moderation_blocklist.js`.
  static const List<String> blockedTerms = [
    // Drugs
    'cocaine', 'heroin', 'meth', 'methamphetamine', 'fentanyl', 'crack cocaine',
    'weed for sale', 'sell weed', 'weed', 'drugs', 'marijuana', 'marihuana',
    'marijuana for sale', 'ganja', 'ganja sale', 'chamba', 'dagga',
    'mdma', 'ecstasy pills', 'lsd blotter', 'opium',
    // Weapons
    'ak47', 'ak-47', 'assault rifle', 'handgun for sale', 'pistol for sale',
    'gun for sale', 'firearm', 'ammunition for sale', 'grenade', 'bomb making',
    'silencer', 'suppressor','mfuti',
    // Stolen / illicit
    'stolen phone', 'stolen goods', 'hot phone', 'cloned sim', 'fake passport',
    'fake id', 'counterfeit money', 'counterfeit notes', 'black money',
    // Adult / exploitation
    'escort service', 'sex for sale', 'prostitute', 'child porn', 'underage sex',
    'nude video sale', 'hule', 'mbolo', 'machende', 'nyini', 'kuchinda',
    'porno', 'kubunyula', 'nyere','phwala','kupwala',
    // Fraud
    'hacked account', 'stolen card', 'cvv for sale', 'fullz',
  ];

  static String normalize(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Returns matching blocked terms found in [title] + [description], or empty.
  static List<String> findBlockedTerms({
    required String title,
    String? description,
  }) {
    final hay = normalize('$title ${description ?? ''}');
    if (hay.isEmpty) return const [];
    final hits = <String>[];
    for (final term in blockedTerms) {
      final t = normalize(term);
      if (t.isEmpty) continue;
      if (hay.contains(t)) hits.add(term);
    }
    return hits;
  }

  /// Public feed / shop: live only when active, and approved when reviewStatus is set.
  static bool isPubliclyVisible(Map<String, dynamic> data) {
    final review =
        (data['reviewStatus'] ?? '').toString().trim().toLowerCase();
    if (review == 'pending' || review == 'rejected') return false;
    if (review == 'approved') return data['isActive'] == true;
    // Legacy docs without reviewStatus.
    if (data['isActive'] is bool) return data['isActive'] as bool;
    return true;
  }

  static String? clientBlockReason({
    required String title,
    String? description,
  }) {
    final hits = findBlockedTerms(title: title, description: description);
    if (hits.isEmpty) return null;
    return 'This listing may not be allowed on Vero Marketplace '
        'Please remove prohibited content and try again.';
  }
}

import 'package:flutter/material.dart';
import 'package:vero360_app/features/DigitalServices/digital_product.dart';

/// Fixed Netflix plan specs. Monthly MWK prices come from admin / [DigitalProduct].
class NetflixPlanSpec {
  final String key;
  final String title;
  final String qualityLabel;
  final String resolution;
  final String supportedDevices;
  final int simultaneousStreams;
  final int downloadDevices;
  final bool spatialAudio;
  final bool mostPopular;
  final double defaultMwkPrice;
  final Color accent;

  const NetflixPlanSpec({
    required this.key,
    required this.title,
    required this.qualityLabel,
    required this.resolution,
    required this.supportedDevices,
    required this.simultaneousStreams,
    required this.downloadDevices,
    this.spatialAudio = false,
    this.mostPopular = false,
    required this.defaultMwkPrice,
    this.accent = const Color(0xFFE50914),
  });

  List<String> get featureLines => [
        'Video and sound quality — $qualityLabel',
        'Resolution — $resolution',
        if (spatialAudio) 'Spatial audio (immersive sound) — included',
        'Supported devices — $supportedDevices',
        'Devices your household can watch at the same time — $simultaneousStreams',
        'Download devices — $downloadDevices',
      ];
}

const List<NetflixPlanSpec> kNetflixPlanSpecs = [
  NetflixPlanSpec(
    key: 'netflix_mobile',
    title: 'Mobile 480p',
    qualityLabel: 'Fair',
    resolution: '480p',
    supportedDevices: 'Mobile phone, tablet',
    simultaneousStreams: 1,
    downloadDevices: 1,
    defaultMwkPrice: 8000,
  ),
  NetflixPlanSpec(
    key: 'netflix_basic',
    title: 'Basic 720p',
    qualityLabel: 'Good',
    resolution: '720p (HD)',
    supportedDevices: 'TV, computer, mobile phone, tablet',
    simultaneousStreams: 1,
    downloadDevices: 1,
    defaultMwkPrice: 12000,
  ),
  NetflixPlanSpec(
    key: 'netflix_standard',
    title: 'Standard 1080p',
    qualityLabel: 'Great',
    resolution: '1080p (Full HD)',
    supportedDevices: 'TV, computer, mobile phone, tablet',
    simultaneousStreams: 2,
    downloadDevices: 2,
    defaultMwkPrice: 15000,
  ),
  NetflixPlanSpec(
    key: 'netflix_premium',
    title: 'Premium 4K + HDR',
    qualityLabel: 'Best',
    resolution: '4K (Ultra HD) + HDR',
    supportedDevices: 'TV, computer, mobile phone, tablet',
    simultaneousStreams: 4,
    downloadDevices: 6,
    spatialAudio: true,
    mostPopular: true,
    defaultMwkPrice: 20000,
  ),
];

bool isNetflixHubKey(String key) => key.trim().toLowerCase() == 'netflix';

bool isNetflixPlanKey(String key) =>
    key.trim().toLowerCase().startsWith('netflix_');

NetflixPlanSpec? netflixPlanSpecForKey(String key) {
  final k = key.trim().toLowerCase();
  for (final s in kNetflixPlanSpecs) {
    if (s.key == k) return s;
  }
  return null;
}

/// Catalog products for each Netflix plan (prices overridden by admin).
const List<DigitalProduct> kNetflixPlanProducts = [
  DigitalProduct(
    key: 'netflix_mobile',
    name: 'Netflix Mobile 480p',
    subtitle: '1-month · 480p',
    category: 'streaming',
    accent: Color(0xFFE50914),
    brandTag: 'Netflix',
    logoAsset: 'assets/brands/netflix.png',
    icon: Icons.movie_creation_outlined,
    fixedMwkPrice: 8000,
  ),
  DigitalProduct(
    key: 'netflix_basic',
    name: 'Netflix Basic 720p',
    subtitle: '1-month · 720p (HD)',
    category: 'streaming',
    accent: Color(0xFFE50914),
    brandTag: 'Netflix',
    logoAsset: 'assets/brands/netflix.png',
    icon: Icons.movie_creation_outlined,
    fixedMwkPrice: 12000,
  ),
  DigitalProduct(
    key: 'netflix_standard',
    name: 'Netflix Standard 1080p',
    subtitle: '1-month · 1080p (Full HD)',
    category: 'streaming',
    accent: Color(0xFFE50914),
    brandTag: 'Netflix',
    logoAsset: 'assets/brands/netflix.png',
    icon: Icons.movie_creation_outlined,
    fixedMwkPrice: 15000,
  ),
  DigitalProduct(
    key: 'netflix_premium',
    name: 'Netflix Premium 4K + HDR',
    subtitle: '1-month · 4K + HDR',
    category: 'streaming',
    accent: Color(0xFFE50914),
    brandTag: 'Popular',
    logoAsset: 'assets/brands/netflix.png',
    icon: Icons.movie_creation_outlined,
    fixedMwkPrice: 20000,
  ),
];

List<DigitalProduct> buildNetflixPlanProducts() =>
    List<DigitalProduct>.from(kNetflixPlanProducts);


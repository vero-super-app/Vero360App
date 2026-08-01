// lib/models/serviceprovider_model.dart
import 'package:vero360_app/config/api_config.dart';

class ServiceProvider {
  final int? id;
  final String serviceProviderId;
  final String businessName;
  final String? businessDescription;
  final String? status;
  final String? openingHours;
  final String? logoUrl;
  final bool? isVerified;
  final double? rating;

  ServiceProvider({
    this.id,
    required this.serviceProviderId,
    required this.businessName,
    this.businessDescription,
    this.status,
    this.openingHours,
    this.logoUrl,
    this.isVerified,
    this.rating,
  });

  factory ServiceProvider.fromJson(Map<String, dynamic> json) {
    double? d(v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
    String? logo(Map<String, dynamic> m) {
      final raw =
          (m['logoUrl'] ?? m['logourl'] ?? m['logoimage'])?.toString().trim();
      if (raw == null || raw.isEmpty) return null;
      return raw.startsWith('http') ? raw : '${ApiConfig.prod}$raw';
    }

    return ServiceProvider(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}'),
      serviceProviderId:
          (json['serviceProviderId'] ?? json['ServiceProviderID'] ?? '')
              .toString(),
      businessName: (json['businessName'] ?? '').toString(),
      businessDescription: json['businessDescription']?.toString(),
      status: json['status']?.toString(),
      openingHours: json['openingHours']?.toString(),
      logoUrl: logo(json),
      isVerified: json['isVerified'] as bool?,
      rating: d(json['rating']),
    );
  }
}

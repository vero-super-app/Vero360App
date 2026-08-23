class TenderPost {
  final String id;
  final String title;
  final String description;
  final String? buyer;
  final String? reference;
  final String? location;
  final String? publishedAt;
  final String? closingAt;
  final String tenderUrl;
  final String? documentUrl;
  final String source;
  final String externalId;
  final bool active;

  const TenderPost({
    required this.id,
    required this.title,
    required this.description,
    this.buyer,
    this.reference,
    this.location,
    this.publishedAt,
    this.closingAt,
    required this.tenderUrl,
    this.documentUrl,
    required this.source,
    required this.externalId,
    this.active = true,
  });

  factory TenderPost.fromJson(Map<String, dynamic> json) {
    String? opt(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return TenderPost(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Tender').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      buyer: opt(json['buyer']),
      reference: opt(json['reference']),
      location: opt(json['location']),
      publishedAt: opt(json['publishedAt']),
      closingAt: opt(json['closingAt']),
      tenderUrl: (json['tenderUrl'] ?? '').toString().trim(),
      documentUrl: opt(json['documentUrl']),
      source: (json['source'] ?? 'manual').toString().trim(),
      externalId: (json['externalId'] ?? json['id'] ?? '').toString(),
      active: json['active'] != false,
    );
  }

  String get sourceLabel {
    switch (source.toLowerCase()) {
      case 'malawitenders':
        return 'MalawiTenders';
      case 'maneps':
        return 'MANEPS';
      case 'ppda':
        return 'PPDA';
      case 'manual':
        return 'Vero360';
      default:
        return source.isEmpty ? 'Tender' : source;
    }
  }

  DateTime? get closingDate {
    if (closingAt == null) return null;
    return DateTime.tryParse(closingAt!);
  }

  bool get isClosed {
    final d = closingDate;
    if (d == null) return false;
    return d.isBefore(DateTime.now());
  }

  bool get isClosingSoon {
    final d = closingDate;
    if (d == null) return false;
    final now = DateTime.now();
    if (d.isBefore(now)) return false;
    return d.difference(now).inDays <= 7;
  }
}

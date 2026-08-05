// lib/models/job.models.dart

enum JobRegion {
  malawi,
  international,
}

enum JobSource {
  manual,
  remotive,
  jooble,
  unknown,
}

class JobPost {
  final int id;
  final String position;
  final String description;
  final String jobLink;
  final String? photoUrl;
  final bool isActive;
  final DateTime? createdAt;
  final JobRegion region;
  final String? company;
  final String? location;
  final bool isRemote;
  final JobSource source;
  final String? externalId;

  JobPost({
    required this.id,
    required this.position,
    required this.description,
    required this.jobLink,
    this.photoUrl,
    required this.isActive,
    this.createdAt,
    this.region = JobRegion.malawi,
    this.company,
    this.location,
    this.isRemote = false,
    this.source = JobSource.manual,
    this.externalId,
  });

  bool get isExternal =>
      source == JobSource.remotive || source == JobSource.jooble;

  /// Prefer apply URL aliases from synced providers.
  String get applyLink {
    final link = jobLink.trim();
    return link;
  }

  factory JobPost.fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    final id = idRaw is int ? idRaw : int.tryParse('$idRaw') ?? 0;

    final regionRaw =
        (json['region'] ?? json['jobRegion'] ?? '').toString().toLowerCase();
    final region = regionRaw == 'international'
        ? JobRegion.international
        : JobRegion.malawi;

    final sourceRaw =
        (json['source'] ?? '').toString().trim().toLowerCase();
    final source = switch (sourceRaw) {
      'remotive' => JobSource.remotive,
      'jooble' => JobSource.jooble,
      'manual' => JobSource.manual,
      '' => JobSource.manual,
      _ => JobSource.unknown,
    };

    // Backend entity uses jobLink; some providers may send url / applyUrl / link.
    final link = (json['jobLink'] ??
            json['applyUrl'] ??
            json['apply_url'] ??
            json['url'] ??
            json['link'] ??
            '')
        .toString()
        .trim();

    return JobPost(
      id: id,
      position: (json['position'] ?? json['title'] ?? 'Untitled').toString(),
      description: (json['description'] ?? '').toString(),
      jobLink: link,
      photoUrl: json['photoUrl']?.toString() ?? json['company_logo']?.toString(),
      isActive: json['isActive'] == true ||
          json['isActive'] == 1 ||
          json['isActive'] == 'true' ||
          json['isActive'] == null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      region: region,
      company: () {
        final c = (json['company'] ?? json['company_name'] ?? '')
            .toString()
            .trim();
        return c.isEmpty ? null : c;
      }(),
      location: () {
        final l =
            (json['location'] ?? json['candidate_required_location'] ?? '')
                .toString()
                .trim();
        return l.isEmpty ? null : l;
      }(),
      isRemote: json['isRemote'] == true ||
          json['isRemote'] == 1 ||
          json['isRemote'] == 'true' ||
          json['remote'] == true,
      source: source,
      externalId: () {
        final e = (json['externalId'] ?? json['external_id'] ?? '')
            .toString()
            .trim();
        return e.isEmpty ? null : e;
      }(),
    );
  }
}

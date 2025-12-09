// lib/models/job.models.dart

class JobPost {
  final int id;
  final String position;
  final String description;
  final String jobLink;
  final String? photoUrl;
  final bool isActive;
  final DateTime? createdAt;

  JobPost({
    required this.id,
    required this.position,
    required this.description,
    required this.jobLink,
    this.photoUrl,
    required this.isActive,
    this.createdAt,
  });

  factory JobPost.fromJson(Map<String, dynamic> json) {
    return JobPost(
      id: json['id'] as int,
      position: json['position'] as String,
      description: json['description'] as String,
      jobLink: json['jobLink'] as String,
      photoUrl: json['photoUrl'] as String?,
      isActive: (json['isActive'] as bool?) ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

enum AttachmentType { image, video, audio, file, document }

class Attachment {
  final String id;
  final String messageId;
  final String uploadedBy;
  final AttachmentType type;
  final String filename;
  final String url;
  final String? thumbnailUrl;
  final int sizeBytes;
  final String? mimeType;
  final DateTime uploadedAt;
  final double uploadProgress; // 0.0 to 1.0
  final bool isUploading;
  final String? errorMessage;

  // Media-specific metadata
  final int? imageWidth;
  final int? imageHeight;
  final int? videoDurationMs;
  final int? audioDurationMs;

  Attachment({
    required this.id,
    required this.messageId,
    required this.uploadedBy,
    required this.type,
    required this.filename,
    required this.url,
    this.thumbnailUrl,
    required this.sizeBytes,
    this.mimeType,
    required this.uploadedAt,
    this.uploadProgress = 0.0,
    this.isUploading = false,
    this.errorMessage,
    this.imageWidth,
    this.imageHeight,
    this.videoDurationMs,
    this.audioDurationMs,
  });

  factory Attachment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Attachment(
      id: doc.id,
      messageId: data['messageId'] ?? '',
      uploadedBy: data['uploadedBy'] ?? '',
      type: _parseAttachmentType(data['type'] ?? 'file'),
      filename: data['filename'] ?? '',
      url: data['url'] ?? '',
      thumbnailUrl: data['thumbnailUrl'],
      sizeBytes: data['sizeBytes'] ?? 0,
      mimeType: data['mimeType'],
      uploadedAt: (data['uploadedAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      uploadProgress: (data['uploadProgress'] as num?)?.toDouble() ?? 1.0,
      isUploading: data['isUploading'] ?? false,
      errorMessage: data['errorMessage'],
      imageWidth: data['imageWidth'],
      imageHeight: data['imageHeight'],
      videoDurationMs: data['videoDurationMs'],
      audioDurationMs: data['audioDurationMs'],
    );
  }

  Map<String, dynamic> toFirestore() => {
    'messageId': messageId,
    'uploadedBy': uploadedBy,
    'type': _attachmentTypeToString(type),
    'filename': filename,
    'url': url,
    'thumbnailUrl': thumbnailUrl,
    'sizeBytes': sizeBytes,
    'mimeType': mimeType,
    'uploadedAt': Timestamp.fromDate(uploadedAt),
    'uploadProgress': uploadProgress,
    'isUploading': isUploading,
    'errorMessage': errorMessage,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'videoDurationMs': videoDurationMs,
    'audioDurationMs': audioDurationMs,
  };

  Attachment copyWith({
    String? id,
    String? messageId,
    String? uploadedBy,
    AttachmentType? type,
    String? filename,
    String? url,
    String? thumbnailUrl,
    int? sizeBytes,
    String? mimeType,
    DateTime? uploadedAt,
    double? uploadProgress,
    bool? isUploading,
    String? errorMessage,
    int? imageWidth,
    int? imageHeight,
    int? videoDurationMs,
    int? audioDurationMs,
  }) {
    return Attachment(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      type: type ?? this.type,
      filename: filename ?? this.filename,
      url: url ?? this.url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType ?? this.mimeType,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      isUploading: isUploading ?? this.isUploading,
      errorMessage: errorMessage ?? this.errorMessage,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      videoDurationMs: videoDurationMs ?? this.videoDurationMs,
      audioDurationMs: audioDurationMs ?? this.audioDurationMs,
    );
  }

  String get displayName => filename;

  String get sizeDisplay {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool get isImage => type == AttachmentType.image;
  bool get isVideo => type == AttachmentType.video;
  bool get isAudio => type == AttachmentType.audio;
  bool get isDocument => type == AttachmentType.document;
}

AttachmentType _parseAttachmentType(String type) {
  switch (type.toLowerCase()) {
    case 'image':
      return AttachmentType.image;
    case 'video':
      return AttachmentType.video;
    case 'audio':
      return AttachmentType.audio;
    case 'document':
      return AttachmentType.document;
    case 'file':
    default:
      return AttachmentType.file;
  }
}

String _attachmentTypeToString(AttachmentType type) {
  return type.toString().split('.').last;
}

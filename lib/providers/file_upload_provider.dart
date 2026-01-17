import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vero360_app/models/attachment_model.dart';
import 'package:vero360_app/services/file_upload_service.dart';

// File upload service provider
final fileUploadServiceProvider = Provider((ref) {
  return FileUploadServiceImpl();
});

// Upload progress tracking by file ID
final uploadProgressProvider = StateProvider<Map<String, double>>(
  (ref) => <String, double>{},
);

// Upload errors by file ID
final uploadErrorsProvider = StateProvider<Map<String, String>>(
  (ref) => <String, String>{},
);

// Current uploads (file IDs)
final currentUploadsProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

// Cache for uploaded attachments
final attachmentCacheProvider = StateProvider<Map<String, Attachment>>(
  (ref) => <String, Attachment>{},
);

/// Family provider for individual message attachments
final messageAttachmentsProvider =
    StreamProvider.family<List<Attachment>, String>((ref, messageId) {
  final service = ref.watch(fileUploadServiceProvider);
  return service.messageAttachmentsStream(messageId);
});

/// Notifier for managing file uploads
class FileUploadNotifier extends StateNotifier<Map<String, double>> {
  final FileUploadServiceImpl _service;
  final Ref ref;

  FileUploadNotifier(this._service, this.ref) : super(<String, double>{});

  /// Upload a file with progress tracking
  Future<Attachment?> uploadFile({
    required File file,
    required String messageId,
    required String uploadedBy,
    required AttachmentType type,
  }) async {
    final fileId = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';

    try {
      // Mark as uploading
      ref.read(currentUploadsProvider.notifier).state = {
        ...ref.read(currentUploadsProvider),
        fileId,
      };

      // Upload with progress callback
      final attachment = await _service.uploadFile(
        file: file,
        messageId: messageId,
        uploadedBy: uploadedBy,
        type: type,
        onProgress: (progress) {
          // Update progress
          state = {
            ...state,
            fileId: progress,
          };
          final currentProgress = ref.read(uploadProgressProvider);
          ref.read(uploadProgressProvider.notifier).state = {
            ...currentProgress,
            fileId: progress,
          };
        },
      );

      // Cache the attachment
      final currentCache = ref.read(attachmentCacheProvider);
      ref.read(attachmentCacheProvider.notifier).state = {
        ...currentCache,
        attachment.id: attachment,
      };

      // Clear from current uploads
      final uploads = ref.read(currentUploadsProvider);
      uploads.remove(fileId);
      ref.read(currentUploadsProvider.notifier).state = {...uploads};

      // Clear progress
      final progressMap = ref.read(uploadProgressProvider);
      progressMap.remove(fileId);
      ref.read(uploadProgressProvider.notifier).state = {...progressMap};

      return attachment;
    } catch (e) {
      // Store error
      final currentErrors = ref.read(uploadErrorsProvider);
      ref.read(uploadErrorsProvider.notifier).state = {
        ...currentErrors,
        fileId: e.toString(),
      };

      // Clear from current uploads
      final uploads = ref.read(currentUploadsProvider);
      uploads.remove(fileId);
      ref.read(currentUploadsProvider.notifier).state = {...uploads};

      return null;
    }
  }

  /// Delete an attachment
  Future<void> deleteAttachment(String attachmentId, String url) async {
    try {
      await _service.deleteAttachment(attachmentId, url);

      // Remove from cache
      final cache = ref.read(attachmentCacheProvider);
      cache.remove(attachmentId);
      ref.read(attachmentCacheProvider.notifier).state = {...cache};
    } catch (e) {
      developer.log('[FileUploadNotifier] Error deleting attachment: $e');
    }
  }

  /// Delete all attachments for a message
  Future<void> deleteMessageAttachments(String messageId) async {
    try {
      await _service.deleteMessageAttachments(messageId);

      // Remove from cache by messageId
      final cache = ref.read(attachmentCacheProvider);
      cache.removeWhere((key, value) => value.messageId == messageId);
      ref.read(attachmentCacheProvider.notifier).state = {...cache};
    } catch (e) {
      developer.log('[FileUploadNotifier] Error deleting message attachments: $e');
    }
  }

  /// Get attachment from cache or fetch
  Future<Attachment?> getAttachment(String attachmentId) async {
    // Check cache first
    final cached = ref.read(attachmentCacheProvider)[attachmentId];
    if (cached != null) return cached;

    // Fetch from service
    try {
      final attachment = await _service.getAttachment(attachmentId);
      if (attachment != null) {
        // Cache it
        final currentCache = ref.read(attachmentCacheProvider);
        ref.read(attachmentCacheProvider.notifier).state = {
          ...currentCache,
          attachmentId: attachment,
        };
      }
      return attachment;
    } catch (e) {
      developer.log('[FileUploadNotifier] Error getting attachment: $e');
      return null;
    }
  }
}

/// Provider for the file upload notifier
final fileUploadNotifierProvider =
    StateNotifierProvider<FileUploadNotifier, Map<String, double>>((ref) {
  final service = ref.watch(fileUploadServiceProvider);
  return FileUploadNotifier(service, ref);
});

/// Helper to get upload progress for a specific file
final uploadProgressFamily = Provider.family<double, String>((ref, fileId) {
  final progress = ref.watch(uploadProgressProvider);
  return progress[fileId] ?? 0.0;
});

/// Helper to get upload error for a specific file
final uploadErrorFamily = Provider.family<String?, String>((ref, fileId) {
  final errors = ref.watch(uploadErrorsProvider);
  return errors[fileId];
});

/// Helper to check if a file is currently uploading
final isUploadingFamily = Provider.family<bool, String>((ref, fileId) {
  final uploads = ref.watch(currentUploadsProvider);
  return uploads.contains(fileId);
});

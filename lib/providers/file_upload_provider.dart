import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vero360_app/models/attachment_model.dart';
import 'dart:developer' as developer;

// =============== UPLOAD STATE PROVIDERS ===============

/// Map of ongoing uploads by message ID: {messageId: {attachmentId: progress}}
final uploadProgressProvider =
    StateProvider<Map<String, Map<String, double>>>((ref) => {});

/// Currently uploading attachments
final uploadingAttachmentsProvider =
    StateProvider<Map<String, Attachment>>((ref) => {});

/// Failed uploads
final failedUploadsProvider = StateProvider<Map<String, String>>((ref) => {});

/// Upload queue (pending uploads)
final uploadQueueProvider = StateProvider<List<Attachment>>((ref) => []);

// =============== ACTION PROVIDERS ===============

/// Provider for file upload service methods
final fileUploadServiceProvider = Provider((ref) {
  return FileUploadService(ref: ref);
});

class FileUploadService {
  final Ref ref;

  FileUploadService({required this.ref});

  /// Start uploading a file
  Future<void> uploadFile({
    required Attachment attachment,
    required Function(double progress) onProgress,
  }) async {
    try {
      // Add to uploading
      final uploading = ref.read(uploadingAttachmentsProvider);
      ref.read(uploadingAttachmentsProvider.notifier).state = {
        ...uploading,
        attachment.id: attachment.copyWith(isUploading: true),
      };

      // Simulate progress updates
      for (int i = 0; i <= 10; i++) {
        final progress = i / 10;
        onProgress(progress);

        // Update provider
        _updateProgress(
          messageId: attachment.messageId,
          attachmentId: attachment.id,
          progress: progress,
        );

        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Mark as complete
      _updateProgress(
        messageId: attachment.messageId,
        attachmentId: attachment.id,
        progress: 1.0,
      );

      // Remove from uploading
      final updated = Map<String, Attachment>.from(
        ref.read(uploadingAttachmentsProvider),
      );
      updated.remove(attachment.id);
      ref.read(uploadingAttachmentsProvider.notifier).state = updated;
    } catch (e) {
      developer.log('[FileUploadService] Upload failed: $e');
      final failed = ref.read(failedUploadsProvider);
      ref.read(failedUploadsProvider.notifier).state = {
        ...failed,
        attachment.id: e.toString(),
      };

      // Remove from uploading on error
      final updated = Map<String, Attachment>.from(
        ref.read(uploadingAttachmentsProvider),
      );
      updated.remove(attachment.id);
      ref.read(uploadingAttachmentsProvider.notifier).state = updated;
      rethrow;
    }
  }

  /// Retry failed upload
  Future<void> retryUpload(String attachmentId) async {
    try {
      final failed = ref.read(failedUploadsProvider);
      final updatedFailed = Map<String, String>.from(failed);
      updatedFailed.remove(attachmentId);
      ref.read(failedUploadsProvider.notifier).state = updatedFailed;
    } catch (e) {
      developer.log('[FileUploadService] Retry failed: $e');
      rethrow;
    }
  }

  /// Cancel upload
  Future<void> cancelUpload(String attachmentId) async {
    try {
      // Remove from uploading
      final uploading = Map<String, Attachment>.from(
        ref.read(uploadingAttachmentsProvider),
      );
      uploading.remove(attachmentId);
      ref.read(uploadingAttachmentsProvider.notifier).state = uploading;

      // Remove from progress
      final progressMap = ref.read(uploadProgressProvider);
      for (final entry in progressMap.entries) {
        final msgMap = Map<String, double>.from(entry.value);
        msgMap.remove(attachmentId);
        progressMap[entry.key] = msgMap;
      }
      ref.read(uploadProgressProvider.notifier).state = progressMap;
    } catch (e) {
      developer.log('[FileUploadService] Cancel failed: $e');
      rethrow;
    }
  }

  /// Add to upload queue
  Future<void> queueUpload(Attachment attachment) async {
    try {
      final queue = ref.read(uploadQueueProvider);
      ref.read(uploadQueueProvider.notifier).state = [...queue, attachment];
    } catch (e) {
      developer.log('[FileUploadService] Queue failed: $e');
      rethrow;
    }
  }

  /// Remove from upload queue
  Future<void> dequeueUpload(String attachmentId) async {
    try {
      final queue = ref.read(uploadQueueProvider);
      ref.read(uploadQueueProvider.notifier).state = [
        for (final a in queue)
          if (a.id != attachmentId) a,
      ];
    } catch (e) {
      developer.log('[FileUploadService] Dequeue failed: $e');
      rethrow;
    }
  }

  /// Get upload progress for a specific attachment
  double getUploadProgress(String messageId, String attachmentId) {
    final progressMap = ref.read(uploadProgressProvider);
    return progressMap[messageId]?[attachmentId] ?? 0.0;
  }

  /// Check if attachment is uploading
  bool isUploading(String attachmentId) {
    return ref.read(uploadingAttachmentsProvider).containsKey(attachmentId);
  }

  /// Check if upload failed
  bool hasFailed(String attachmentId) {
    return ref.read(failedUploadsProvider).containsKey(attachmentId);
  }

  void _updateProgress({
    required String messageId,
    required String attachmentId,
    required double progress,
  }) {
    final progressMap = ref.read(uploadProgressProvider);
    final msgMap = Map<String, double>.from(progressMap[messageId] ?? {});
    msgMap[attachmentId] = progress;
    ref.read(uploadProgressProvider.notifier).state = {
      ...progressMap,
      messageId: msgMap,
    };
  }
}

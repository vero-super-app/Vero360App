import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:vero360_app/GeneralModels/attachment_model.dart';

class FileUploadServiceImpl {
  static const String _attachmentsCollection = 'attachments';
  static const String _storageFolder = 'chat_attachments';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload file to Firebase Storage and save metadata
  Future<Attachment> uploadFile({
    required File file,
    required String messageId,
    required String uploadedBy,
    required AttachmentType type,
    required Function(double progress) onProgress,
  }) async {
    try {
      final filename = file.path.split('/').last;
      final attachmentId =
          'att_${DateTime.now().millisecondsSinceEpoch}_$filename';

      // Determine MIME type based on extension
      final mimeType = _getMimeType(file.path);

      // Upload file to Storage
      final storageRef = _storage
          .ref()
          .child(_storageFolder)
          .child(messageId)
          .child(attachmentId);

      final uploadTask = storageRef.putFile(file);

      // Monitor upload progress
      uploadTask.snapshotEvents.listen((taskSnapshot) {
        final progress = taskSnapshot.bytesTransferred /
            taskSnapshot.totalBytes;
        onProgress(progress);
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Create thumbnail for images/videos (optional - would need image processing)
      String? thumbnailUrl;
      if (type == AttachmentType.image || type == AttachmentType.video) {
        thumbnailUrl = downloadUrl; // In production, generate thumbnail
      }

      // Save attachment metadata to Firestore
      final attachment = Attachment(
        id: attachmentId,
        messageId: messageId,
        uploadedBy: uploadedBy,
        type: type,
        filename: filename,
        url: downloadUrl,
        thumbnailUrl: thumbnailUrl,
        sizeBytes: await file.length(),
        mimeType: mimeType,
        uploadedAt: DateTime.now(),
        uploadProgress: 1.0,
        isUploading: false,
      );

      await _firestore
          .collection(_attachmentsCollection)
          .doc(attachmentId)
          .set(attachment.toFirestore());

      return attachment;
    } catch (e) {
      print('[FileUploadServiceImpl] uploadFile error: $e');
      rethrow;
    }
  }

  /// Get attachment by ID
  Future<Attachment?> getAttachment(String attachmentId) async {
    try {
      final doc = await _firestore
          .collection(_attachmentsCollection)
          .doc(attachmentId)
          .get();

      if (!doc.exists) return null;
      return Attachment.fromFirestore(doc);
    } catch (e) {
      print('[FileUploadServiceImpl] getAttachment error: $e');
      rethrow;
    }
  }

  /// Get attachments for a message
  Future<List<Attachment>> getMessageAttachments(String messageId) async {
    try {
      final query = await _firestore
          .collection(_attachmentsCollection)
          .where('messageId', isEqualTo: messageId)
          .get();

      return query.docs
          .map((doc) => Attachment.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('[FileUploadServiceImpl] getMessageAttachments error: $e');
      rethrow;
    }
  }

  /// Stream of attachments for a message
  Stream<List<Attachment>> messageAttachmentsStream(String messageId) {
    return _firestore
        .collection(_attachmentsCollection)
        .where('messageId', isEqualTo: messageId)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => Attachment.fromFirestore(doc))
        .toList());
  }

  /// Delete attachment (remove from Storage and Firestore)
  Future<void> deleteAttachment(String attachmentId, String url) async {
    try {
      // Delete from Firestore
      await _firestore
          .collection(_attachmentsCollection)
          .doc(attachmentId)
          .delete();

      // Delete from Storage
      try {
        final ref = FirebaseStorage.instance.refFromURL(url);
        await ref.delete();
      } catch (e) {
        print('[FileUploadServiceImpl] Could not delete from storage: $e');
      }
    } catch (e) {
      print('[FileUploadServiceImpl] deleteAttachment error: $e');
      rethrow;
    }
  }

  /// Delete all attachments for a message
  Future<void> deleteMessageAttachments(String messageId) async {
    try {
      final attachments = await getMessageAttachments(messageId);
      for (final att in attachments) {
        await deleteAttachment(att.id, att.url);
      }
    } catch (e) {
      print('[FileUploadServiceImpl] deleteMessageAttachments error: $e');
      rethrow;
    }
  }

  /// Get total attachment size for a message
  Future<int> getMessageAttachmentSize(String messageId) async {
    try {
      final attachments = await getMessageAttachments(messageId);
      return attachments.fold<int>(0, (sum, att) => sum + att.sizeBytes);
    } catch (e) {
      print('[FileUploadServiceImpl] getMessageAttachmentSize error: $e');
      rethrow;
    }
  }

  String _getMimeType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}

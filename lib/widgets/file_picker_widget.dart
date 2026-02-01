import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vero360_app/GeneralModels/attachment_model.dart';
import 'package:vero360_app/Gernalproviders/file_upload_provider.dart';

/// Widget for picking and uploading files
class FilePickerWidget extends ConsumerStatefulWidget {
  final String messageId;
  final String uploadedBy;
  final Function(Attachment) onFileUploaded;
  final VoidCallback? onStartUpload;

  const FilePickerWidget({
    Key? key,
    required this.messageId,
    required this.uploadedBy,
    required this.onFileUploaded,
    this.onStartUpload,
  }) : super(key: key);

  @override
  ConsumerState<FilePickerWidget> createState() => _FilePickerWidgetState();
}

class _FilePickerWidgetState extends ConsumerState<FilePickerWidget> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickAndUploadImage({required bool isCamera}) async {
    try {
      widget.onStartUpload?.call();

      final source = isCamera ? ImageSource.camera : ImageSource.gallery;
      final pickedFile = await _picker.pickImage(source: source);

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        await _uploadFile(file, AttachmentType.image);
      }
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  Future<void> _pickAndUploadVideo() async {
    try {
      widget.onStartUpload?.call();

      final pickedFile = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        await _uploadFile(file, AttachmentType.video);
      }
    } catch (e) {
      _showError('Failed to pick video: $e');
    }
  }

  Future<void> _uploadFile(File file, AttachmentType type) async {
    try {
      final notifier = ref.read(fileUploadNotifierProvider.notifier);
      final attachment = await notifier.uploadFile(
        file: file,
        messageId: widget.messageId,
        uploadedBy: widget.uploadedBy,
        type: type,
      );

      if (attachment != null) {
        widget.onFileUploaded(attachment);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${attachment.displayName} uploaded successfully',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      _showError('Upload failed: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showPickerBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Take Photo'),
            onTap: () {
              Navigator.pop(context);
              _pickAndUploadImage(isCamera: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose Photo'),
            onTap: () {
              Navigator.pop(context);
              _pickAndUploadImage(isCamera: false);
            },
          ),
          ListTile(
            leading: const Icon(Icons.videocam),
            title: const Text('Choose Video'),
            onTap: () {
              Navigator.pop(context);
              _pickAndUploadVideo();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.attachment),
      tooltip: 'Attach file',
      onPressed: _showPickerBottomSheet,
    );
  }
}

/// Widget for displaying attachment previews
class AttachmentPreviewWidget extends ConsumerWidget {
  final Attachment attachment;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  const AttachmentPreviewWidget({
    Key? key,
    required this.attachment,
    this.onDelete,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[200],
        ),
        child: Stack(
          children: [
            // Attachment content
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (attachment.isImage)
                  Image.network(
                    attachment.url,
                    height: 150,
                    width: 150,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.image, size: 50),
                  )
                else if (attachment.isVideo)
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.network(
                        attachment.thumbnailUrl ?? attachment.url,
                        height: 150,
                        width: 150,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.video_library, size: 50),
                      ),
                      const Icon(
                        Icons.play_circle_filled,
                        size: 40,
                        color: Colors.white,
                      ),
                    ],
                  )
                else if (attachment.isAudio)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.audio_file, size: 40),
                      const SizedBox(height: 8),
                      Text(
                        attachment.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  )
                else
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.insert_drive_file, size: 40),
                      const SizedBox(height: 8),
                      Text(
                        attachment.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        attachment.sizeDisplay,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            // Delete button
            if (onDelete != null)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // Upload progress indicator
            if (attachment.isUploading)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(attachment.uploadProgress * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Widget for displaying a list of message attachments
class AttachmentListWidget extends ConsumerWidget {
  final String messageId;
  final VoidCallback? onAttachmentDeleted;

  const AttachmentListWidget({
    Key? key,
    required this.messageId,
    this.onAttachmentDeleted,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentsAsync = ref.watch(messageAttachmentsProvider(messageId));

    return attachmentsAsync.when(
      data: (attachments) {
        if (attachments.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: attachments
                  .map((attachment) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AttachmentPreviewWidget(
                          attachment: attachment,
                          onDelete: () {
                            _deleteAttachment(context, ref, attachment);
                          },
                          onTap: () {
                            _viewAttachment(context, attachment);
                          },
                        ),
                      ))
                  .toList(),
            ),
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          height: 50,
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text('Error loading attachments: $error'),
      ),
    );
  }

  void _deleteAttachment(
    BuildContext context,
    WidgetRef ref,
    Attachment attachment,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Attachment'),
        content: Text('Delete ${attachment.displayName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(fileUploadNotifierProvider.notifier)
                  .deleteAttachment(attachment.id, attachment.url)
                  .then((_) {
                onAttachmentDeleted?.call();
                Navigator.pop(context);
              });
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _viewAttachment(BuildContext context, Attachment attachment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(attachment.displayName),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachment.isImage)
                Image.network(attachment.url)
              else if (attachment.isVideo)
                Text('Video: ${attachment.sizeDisplay}')
              else
                Text('File: ${attachment.sizeDisplay}'),
              const SizedBox(height: 16),
              Text('Type: ${attachment.type.toString().split('.').last}'),
              Text('Size: ${attachment.sizeDisplay}'),
              Text(
                'Uploaded: ${attachment.uploadedAt.toString().split('.')[0]}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

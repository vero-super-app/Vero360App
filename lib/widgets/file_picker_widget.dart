import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/models/attachment_model.dart';
import 'package:vero360_app/providers/file_upload_provider.dart';
import 'package:vero360_app/widgets/messaging_colors.dart';

/// File picker action menu
class FilePickerActionMenu extends ConsumerWidget {
  final Function(Attachment) onFilePicked;
  final Function(Attachment) onFilesSelected;

  const FilePickerActionMenu({
    super.key,
    required this.onFilePicked,
    required this.onFilesSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Image option
        _FilePickerOption(
          icon: Icons.image,
          label: 'Photo',
          onTap: () async {
            // Placeholder - would use image_picker package
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Image picker - implement with image_picker package')),
            );
          },
        ),

        // Camera option
        _FilePickerOption(
          icon: Icons.camera_alt,
          label: 'Camera',
          onTap: () async {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Camera - implement with camera package')),
            );
          },
        ),

        // Video option
        _FilePickerOption(
          icon: Icons.videocam,
          label: 'Video',
          onTap: () async {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video picker - implement with image_picker package')),
            );
          },
        ),

        // Audio option
        _FilePickerOption(
          icon: Icons.audio_file,
          label: 'Audio',
          onTap: () async {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Audio recorder - implement with audio_waveforms package')),
            );
          },
        ),

        // File option
        _FilePickerOption(
          icon: Icons.description,
          label: 'File',
          onTap: () async {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File picker - implement with file_picker package')),
            );
          },
        ),
      ],
    );
  }
}

class _FilePickerOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FilePickerOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          child: Row(
            children: [
              Icon(
                icon,
                color: MessagingColors.brandOrange,
                size: 24,
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  color: MessagingColors.title,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Attachment preview widget
class AttachmentPreview extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback? onDelete;

  const AttachmentPreview({
    super.key,
    required this.attachment,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: MessagingColors.border),
        borderRadius: BorderRadius.circular(8),
        color: MessagingColors.surfaceLight,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thumbnail/Preview
          if (attachment.isImage)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                attachment.url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(
                      color: MessagingColors.surfaceLight,
                      child: const Icon(Icons.image_not_supported),
                    ),
              ),
            ),

          if (attachment.isVideo)
            Container(
              height: 120,
              color: MessagingColors.surfaceLight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (attachment.thumbnailUrl != null)
                    Image.network(
                      attachment.thumbnailUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  const Icon(Icons.play_circle_outline,
                      size: 48, color: MessagingColors.brandOrange),
                ],
              ),
            ),

          if (!attachment.isImage && !attachment.isVideo)
            Container(
              height: 80,
              color: MessagingColors.surfaceLight,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Icon(
                      _getFileIcon(attachment.type),
                      size: 48,
                      color: MessagingColors.brandOrange,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: MessagingColors.title,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          attachment.sizeDisplay,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MessagingColors.subtitle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Info bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: MessagingColors.title,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${attachment.sizeDisplay} • ${_formatUploadTime(attachment.uploadedAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: MessagingColors.subtitle,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 20, color: MessagingColors.error),
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(AttachmentType type) {
    switch (type) {
      case AttachmentType.audio:
        return Icons.audio_file;
      case AttachmentType.document:
        return Icons.description;
      default:
        return Icons.file_present;
    }
  }

  String _formatUploadTime(DateTime time) {
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// Upload progress indicator
class UploadProgressIndicator extends ConsumerWidget {
  final String attachmentId;
  final String messageId;

  const UploadProgressIndicator({
    super.key,
    required this.attachmentId,
    required this.messageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploadService = ref.read(fileUploadServiceProvider);
    final progress =
        uploadService.getUploadProgress(messageId, attachmentId);
    final hasError = uploadService.hasFailed(attachmentId);

    if (hasError) {
      return Row(
        children: [
          const Icon(Icons.error_outline,
              color: MessagingColors.error, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Upload failed',
              style: TextStyle(
                fontSize: 12,
                color: MessagingColors.error,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              uploadService.retryUpload(attachmentId);
            },
            child: const Text('Retry'),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: MessagingColors.border,
            valueColor: const AlwaysStoppedAnimation<Color>(
              MessagingColors.uploadProgress,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${(progress * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
            fontSize: 10,
            color: MessagingColors.subtitle,
          ),
        ),
      ],
    );
  }
}

/// Attachment grid for gallery-like display
class AttachmentGrid extends StatelessWidget {
  final List<Attachment> attachments;
  final Function(Attachment)? onDelete;
  final Function(Attachment)? onTap;

  const AttachmentGrid({
    super.key,
    required this.attachments,
    this.onDelete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: attachments.length,
      itemBuilder: (context, index) {
        final att = attachments[index];
        return _AttachmentGridItem(
          attachment: att,
          onDelete: onDelete,
          onTap: onTap,
        );
      },
    );
  }
}

class _AttachmentGridItem extends StatelessWidget {
  final Attachment attachment;
  final Function(Attachment)? onDelete;
  final Function(Attachment)? onTap;

  const _AttachmentGridItem({
    required this.attachment,
    this.onDelete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Thumbnail
        GestureDetector(
          onTap: () => onTap?.call(attachment),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: MessagingColors.surfaceLight,
            ),
            child: attachment.isImage
                ? Image.network(
              attachment.url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.image_not_supported),
            )
                : Container(
              color: MessagingColors.surfaceLight,
              child: const Icon(Icons.file_present),
            ),
          ),
        ),

        // Play icon for videos
        if (attachment.isVideo)
          const Positioned(
            top: 8,
            right: 8,
            child: Icon(Icons.play_circle,
                color: Colors.white, size: 24),
          ),

        // Delete button
        if (onDelete != null)
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: () => onDelete?.call(attachment),
              child: Container(
                decoration: BoxDecoration(
                  color: MessagingColors.error,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.close,
                    color: Colors.white, size: 16),
              ),
            ),
          ),
      ],
    );
  }
}

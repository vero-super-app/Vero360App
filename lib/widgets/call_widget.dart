import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/models/call_model.dart';
import 'package:vero360_app/providers/call_provider.dart';
import 'package:vero360_app/widgets/messaging_colors.dart';

/// Incoming call dialog/widget
class IncomingCallWidget extends ConsumerStatefulWidget {
  final CallSession call;

  const IncomingCallWidget({
    super.key,
    required this.call,
  });

  @override
  ConsumerState<IncomingCallWidget> createState() =>
      _IncomingCallWidgetState();
}

class _IncomingCallWidgetState extends ConsumerState<IncomingCallWidget> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 8,
      backgroundColor: MessagingColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar
            CircleAvatar(
              radius: 48,
              backgroundColor: MessagingColors.brandOrangePale,
              backgroundImage: widget.call.initiatorAvatar != null
                  ? NetworkImage(widget.call.initiatorAvatar!)
                  : null,
              child: widget.call.initiatorAvatar == null
                  ? const Icon(Icons.person,
                  size: 48, color: MessagingColors.brandOrange)
                  : null,
            ),
            const SizedBox(height: 16),

            // Caller name
            Text(
              widget.call.initiatorName ?? 'Unknown User',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: MessagingColors.title,
              ),
            ),
            const SizedBox(height: 8),

            // Call type
            Text(
              widget.call.callType == CallType.video
                  ? 'Video Call'
                  : 'Voice Call',
              style: const TextStyle(
                fontSize: 14,
                color: MessagingColors.subtitle,
              ),
            ),
            const SizedBox(height: 32),

            // Answer & Decline buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline button
                FloatingActionButton(
                  onPressed: () async {
                    await ref
                        .read(callServiceProvider)
                        .declineCall(widget.call);
                    if (context.mounted) Navigator.pop(context);
                  },
                  backgroundColor: MessagingColors.error,
                  child: const Icon(Icons.call_end),
                ),

                // Answer button
                FloatingActionButton(
                  onPressed: () async {
                    await ref
                        .read(callServiceProvider)
                        .answerCall(widget.call);
                    if (context.mounted) Navigator.pop(context);
                  },
                  backgroundColor: MessagingColors.success,
                  child: const Icon(Icons.call),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Active call screen
class ActiveCallWidget extends ConsumerStatefulWidget {
  final CallSession call;

  const ActiveCallWidget({
    super.key,
    required this.call,
  });

  @override
  ConsumerState<ActiveCallWidget> createState() =>
      _ActiveCallWidgetState();
}

class _ActiveCallWidgetState extends ConsumerState<ActiveCallWidget> {
  late int _callDuration;

  @override
  void initState() {
    super.initState();
    _callDuration = 0;
    _startDurationTimer();
  }

  void _startDurationTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;

      setState(() => _callDuration++);
      ref.read(callServiceProvider).updateCallDuration(_callDuration);
      return true;
    });
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isMicEnabled = ref.watch(isMicrophoneEnabledProvider);
    final isCameraEnabled = ref.watch(isCameraEnabledProvider);
    final isSpeakerEnabled = ref.watch(isSpeakerEnabledProvider);
    final callQuality = ref.watch(callQualityProvider);

    return Scaffold(
      backgroundColor: MessagingColors.title,
      body: SafeArea(
        child: Column(
          children: [
            // Top info bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Call duration
                  Text(
                    _formatDuration(_callDuration),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Peer name
                  Text(
                    widget.call.recipientName ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Call quality indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.signal_cellular_alt,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Quality: ${(callQuality * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Peer avatar (placeholder for video)
            if (widget.call.callType == CallType.video)
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: CircleAvatar(
                      radius: 64,
                      backgroundColor: MessagingColors.brandOrangePale,
                      backgroundImage:
                      widget.call.recipientAvatar != null
                          ? NetworkImage(widget.call.recipientAvatar!)
                          : null,
                      child: widget.call.recipientAvatar == null
                          ? const Icon(Icons.person,
                          size: 64, color: MessagingColors.brandOrange)
                          : null,
                    ),
                  ),
                ),
              ),

            const Spacer(),

            // Control buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Microphone toggle
                  FloatingActionButton(
                    heroTag: 'mic',
                    onPressed: () =>
                        ref.read(callServiceProvider).toggleMicrophone(),
                    backgroundColor: isMicEnabled
                        ? MessagingColors.brandOrange
                        : MessagingColors.grey,
                    child: Icon(
                      isMicEnabled ? Icons.mic : Icons.mic_off,
                    ),
                  ),

                  // Camera toggle (only for video calls)
                  if (widget.call.callType == CallType.video)
                    FloatingActionButton(
                      heroTag: 'camera',
                      onPressed: () =>
                          ref.read(callServiceProvider).toggleCamera(),
                      backgroundColor: isCameraEnabled
                          ? MessagingColors.brandOrange
                          : MessagingColors.grey,
                      child: Icon(
                        isCameraEnabled ? Icons.videocam : Icons.videocam_off,
                      ),
                    ),

                  // Speaker toggle
                  FloatingActionButton(
                    heroTag: 'speaker',
                    onPressed: () =>
                        ref.read(callServiceProvider).toggleSpeaker(),
                    backgroundColor: isSpeakerEnabled
                        ? MessagingColors.brandOrange
                        : MessagingColors.grey,
                    child: Icon(
                      isSpeakerEnabled ? Icons.volume_up : Icons.volume_off,
                    ),
                  ),

                  // End call button
                  FloatingActionButton(
                    heroTag: 'end',
                    onPressed: () async {
                      await ref.read(callServiceProvider).endCall();
                      if (context.mounted) Navigator.pop(context);
                    },
                    backgroundColor: MessagingColors.error,
                    child: const Icon(Icons.call_end),
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

/// Call initiation button (for message screens)
class CallInitiationButton extends ConsumerWidget {
  final String recipientId;
  final String recipientName;
  final String? recipientAvatar;
  final CallType callType;

  const CallInitiationButton({
    super.key,
    required this.recipientId,
    required this.recipientName,
    this.recipientAvatar,
    required this.callType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: Icon(
        callType == CallType.video ? Icons.videocam : Icons.call,
        color: MessagingColors.brandOrange,
      ),
      onPressed: () async {
        try {
          await ref.read(callServiceProvider).initiateCall(
            recipientId: recipientId,
            recipientName: recipientName,
            recipientAvatar: recipientAvatar,
            initiatorName: 'You', // Get from context
            initiatorAvatar: null,
            callType: callType,
          );

          // Show active call widget
          if (context.mounted) {
            final activeCall = ref.watch(activeCallProvider);
            if (activeCall != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ActiveCallWidget(call: activeCall),
                ),
              );
            }
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to initiate call: $e')),
            );
          }
        }
      },
    );
  }

  Future<String> _getCurrentUserId() async {
    // Placeholder - get from auth context
    return 'current_user_id';
  }
}

/// Call history list tile
class CallHistoryTile extends StatelessWidget {
  final CallHistoryEntry entry;
  final VoidCallback? onTap;

  const CallHistoryTile({
    super.key,
    required this.entry,
    this.onTap,
  });

  Color _getStatusColor() {
    switch (entry.status) {
      case CallStatus.missed:
        return MessagingColors.callMissed;
      case CallStatus.declined:
        return MessagingColors.callDeclined;
      case CallStatus.failed:
        return MessagingColors.error;
      case CallStatus.ended:
        return MessagingColors.callEnded;
      default:
        return MessagingColors.body;
    }
  }

  IconData _getStatusIcon() {
    switch (entry.status) {
      case CallStatus.missed:
        return Icons.call_missed;
      case CallStatus.declined:
        return Icons.call_end;
      case CallStatus.failed:
        return Icons.error_outline;
      case CallStatus.incoming:
      case CallStatus.active:
      case CallStatus.ended:
        return entry.isIncoming ? Icons.call_received : Icons.call_made;
      default:
        return Icons.call;
    }
  }

  String _getSubtitle() {
    final date = _formatDate(entry.timestamp);
    final duration =
    entry.durationSeconds > 0 ? ' • ${_formatDuration(entry.durationSeconds)}' : '';
    return '$date$duration';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.month}/${date.day}/${date.year}';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    return '${hours}h';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: MessagingColors.brandOrangePale,
        backgroundImage: entry.peerAvatar != null
            ? NetworkImage(entry.peerAvatar!)
            : null,
        child: entry.peerAvatar == null
            ? const Icon(Icons.person,
            color: MessagingColors.brandOrange)
            : null,
      ),
      title: Text(
        entry.peerName ?? 'Unknown',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: MessagingColors.title,
        ),
      ),
      subtitle: Text(
        _getSubtitle(),
        style: const TextStyle(
          fontSize: 12,
          color: MessagingColors.subtitle,
        ),
      ),
      trailing: Icon(
        _getStatusIcon(),
        color: _getStatusColor(),
        size: 20,
      ),
      onTap: onTap,
    );
  }
}

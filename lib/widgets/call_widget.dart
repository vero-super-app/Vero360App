import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/call_model.dart';
import 'package:vero360_app/Gernalproviders/messaging/call_provider.dart';

/// Widget for displaying incoming call UI
class IncomingCallWidget extends ConsumerWidget {
  final CallSession call;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallWidget({
    Key? key,
    required this.call,
    required this.onAccept,
    required this.onDecline,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black87.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Caller avatar
            CircleAvatar(
              radius: 50,
              backgroundImage: call.initiatorAvatar != null
                  ? NetworkImage(call.initiatorAvatar!)
                  : null,
              child: call.initiatorAvatar == null
                  ? Icon(
                      call.callType == CallType.video
                          ? Icons.videocam
                          : Icons.call,
                      size: 40,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(height: 24),

            // Caller name
            Text(
              call.initiatorName ?? 'Unknown',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Call type
            Text(
              call.callType == CallType.video ? 'Video Call' : 'Voice Call',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 32),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline button
                FloatingActionButton(
                  onPressed: onDecline,
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),

                // Accept button
                FloatingActionButton(
                  onPressed: onAccept,
                  backgroundColor: Colors.green,
                  child: Icon(
                    call.callType == CallType.video
                        ? Icons.videocam
                        : Icons.call,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget for active call UI with controls
class ActiveCallWidget extends ConsumerWidget {
  final CallSession call;
  final VoidCallback onEndCall;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleSpeaker;
  final VoidCallback? onSwitchCamera;

  const ActiveCallWidget({
    Key? key,
    required this.call,
    required this.onEndCall,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onToggleSpeaker,
    this.onSwitchCamera,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final callDuration = ref.watch(callDurationProvider);
    final isMicEnabled = ref.watch(isMicrophoneEnabledProvider);
    final isCameraEnabled = ref.watch(isCameraEnabledProvider);
    final isSpeakerEnabled = ref.watch(isSpeakerEnabledProvider);

    return Scaffold(
      body: Stack(
        children: [
          // Video/background area
          Container(
            color: Colors.black,
            child: Center(
              child: call.callType == CallType.video
                  ? const Icon(
                      Icons.videocam,
                      size: 80,
                      color: Colors.grey,
                    )
                  : Icon(
                      Icons.call,
                      size: 80,
                      color: Colors.grey,
                    ),
            ),
          ),

          // Call info overlay
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  call.recipientName ?? 'Unknown',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDuration(callDuration),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[300],
                  ),
                ),
              ],
            ),
          ),

          // Control buttons at bottom
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Microphone toggle
                  _ControlButton(
                    icon: isMicEnabled ? Icons.mic : Icons.mic_off,
                    backgroundColor:
                        isMicEnabled ? Colors.blueGrey : Colors.red,
                    onPressed: onToggleMic,
                  ),
                  const SizedBox(width: 24),

                  // Camera toggle (video calls only)
                  if (call.callType == CallType.video)
                    _ControlButton(
                      icon:
                          isCameraEnabled ? Icons.videocam : Icons.videocam_off,
                      backgroundColor:
                          isCameraEnabled ? Colors.blueGrey : Colors.red,
                      onPressed: onToggleCamera,
                    ),
                  if (call.callType == CallType.video)
                    const SizedBox(width: 24),

                  // Speaker toggle
                  _ControlButton(
                    icon: isSpeakerEnabled ? Icons.volume_up : Icons.volume_off,
                    backgroundColor:
                        isSpeakerEnabled ? Colors.blueGrey : Colors.red,
                    onPressed: onToggleSpeaker,
                  ),
                  const SizedBox(width: 24),

                  // Switch camera (video calls only)
                  if (call.callType == CallType.video && onSwitchCamera != null)
                    _ControlButton(
                      icon: Icons.flip_camera_ios,
                      backgroundColor: Colors.blueGrey,
                      onPressed: onSwitchCamera!,
                    ),
                  if (call.callType == CallType.video && onSwitchCamera != null)
                    const SizedBox(width: 24),

                  // End call button
                  FloatingActionButton(
                    onPressed: onEndCall,
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.call_end, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

/// Small control button for call controls
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color backgroundColor;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.backgroundColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      mini: true,
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      child: Icon(icon, color: Colors.white),
    );
  }
}

/// Call history item widget
class CallHistoryItemWidget extends StatelessWidget {
  final CallHistoryEntry entry;
  final VoidCallback onTap;

  const CallHistoryItemWidget({
    Key? key,
    required this.entry,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(entry.status);

    return ListTile(
      leading: CircleAvatar(
        backgroundImage:
            entry.peerAvatar != null ? NetworkImage(entry.peerAvatar!) : null,
        child: entry.peerAvatar == null ? const Icon(Icons.person) : null,
      ),
      title: Text(entry.peerName ?? 'Unknown'),
      subtitle: Row(
        children: [
          Icon(
            entry.isIncoming ? Icons.call_received : Icons.call_made,
            size: 16,
            color: statusColor,
          ),
          const SizedBox(width: 8),
          Text(
            entry.callType == CallType.video ? 'Video' : 'Voice',
            style: theme.textTheme.bodySmall,
          ),
          if (entry.durationSeconds > 0) ...[
            const SizedBox(width: 8),
            Text(
              '${entry.durationSeconds} sec',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ],
      ),
      trailing: Icon(
        entry.isIncoming ? Icons.call_received : Icons.call_made,
        color: statusColor,
      ),
      onTap: onTap,
    );
  }

  Color _getStatusColor(CallStatus status) {
    switch (status) {
      case CallStatus.active:
      case CallStatus.ended:
        return Colors.green;
      case CallStatus.missed:
      case CallStatus.declined:
      case CallStatus.failed:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

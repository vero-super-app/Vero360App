import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/models/call_model.dart';
import 'package:vero360_app/providers/messaging/call_provider.dart';
import 'package:vero360_app/services/webrtc_service.dart';
import 'package:vero360_app/widgets/call_widget.dart';

/// Main call screen for handling voice and video calls
class CallScreen extends ConsumerStatefulWidget {
  final CallSession call;
  final bool isInitiator;

  const CallScreen({
    Key? key,
    required this.call,
    this.isInitiator = false,
  }) : super(key: key);

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late WebRTCService _webrtcService;
  Timer? _durationTimer;
  int _callDuration = 0;

  @override
  void initState() {
    super.initState();
    _webrtcService = WebRTCService();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    try {
      // Initialize WebRTC service
      await _webrtcService.initializeCall(
        callId: widget.call.id,
        localUserId: widget.call.initiatorId,
        remoteUserId: widget.call.recipientId,
      );

      // Create local media stream
      final streamCreated = await _webrtcService.createLocalStream(
        audio: true,
        video: widget.call.callType == CallType.video,
      );

      if (!streamCreated) {
        _showError('Failed to access camera/microphone');
        return;
      }

      // If initiator, create offer
      if (widget.isInitiator) {
        final offer = await _webrtcService.createOffer();
        if (offer != null) {
          // Emit offer through WebSocket/signaling
          print('[CallScreen] Created offer: $offer');
        }
      }

      // Start call duration timer
      _startDurationTimer();
    } catch (e) {
      _showError('Failed to initialize call: $e');
    }
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _callDuration++;
      });
      ref.read(callServiceProvider).updateCallDuration(_callDuration);
    });
  }

  Future<void> _handleEndCall() async {
    try {
      _durationTimer?.cancel();
      await _webrtcService.cleanup();
      await ref.read(callServiceProvider).endCall();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('Error ending call: $e');
    }
  }

  Future<void> _handleToggleMic() async {
    await ref.read(callServiceProvider).toggleMicrophone();
    final isMicEnabled = ref.read(isMicrophoneEnabledProvider);
    await _webrtcService.toggleAudio(isMicEnabled);
  }

  Future<void> _handleToggleCamera() async {
    if (widget.call.callType != CallType.video) return;
    await ref.read(callServiceProvider).toggleCamera();
    final isCameraEnabled = ref.read(isCameraEnabledProvider);
    await _webrtcService.toggleVideo(isCameraEnabled);
  }

  Future<void> _handleToggleSpeaker() async {
    await ref.read(callServiceProvider).toggleSpeaker();
  }

  Future<void> _handleSwitchCamera() async {
    await _webrtcService.switchCamera();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _webrtcService.cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Confirm before ending call
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('End Call'),
                content: const Text('Are you sure you want to end this call?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('End Call'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      child: ActiveCallWidget(
        call: widget.call,
        onEndCall: _handleEndCall,
        onToggleMic: _handleToggleMic,
        onToggleCamera: _handleToggleCamera,
        onToggleSpeaker: _handleToggleSpeaker,
        onSwitchCamera:
            widget.call.callType == CallType.video ? _handleSwitchCamera : null,
      ),
    );
  }
}

/// Screen for displaying incoming call with accept/decline options
class IncomingCallScreen extends ConsumerStatefulWidget {
  final CallSession call;

  const IncomingCallScreen({
    Key? key,
    required this.call,
  }) : super(key: key);

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(callServiceProvider).receiveIncomingCall(widget.call);
  }

  Future<void> _handleAccept() async {
    try {
      await ref.read(callServiceProvider).answerCall(widget.call);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => CallScreen(
              call: widget.call,
              isInitiator: false,
            ),
          ),
        );
      }
    } catch (e) {
      _showError('Failed to answer call: $e');
    }
  }

  Future<void> _handleDecline() async {
    try {
      await ref.read(callServiceProvider).declineCall(widget.call);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('Failed to decline call: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: IncomingCallWidget(
          call: widget.call,
          onAccept: _handleAccept,
          onDecline: _handleDecline,
        ),
      ),
    );
  }
}

/// Screen for displaying call history
class CallHistoryScreen extends ConsumerWidget {
  const CallHistoryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callHistory = ref.watch(callHistoryProvider);
    final theme = Theme.of(context);

    if (callHistory.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Call History'),
        ),
        body: Center(
          child: Text(
            'No call history',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call History'),
        actions: [
          if (callHistory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear history',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear Call History'),
                    content: const Text(
                      'Are you sure you want to clear all call history?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          ref.read(callHistoryProvider.notifier).state = [];
                          Navigator.pop(context);
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: ListView.separated(
        itemCount: callHistory.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final entry = callHistory[index];
          return CallHistoryItemWidget(
            entry: entry,
            onTap: () {
              // Show call details
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(entry.peerName ?? 'Unknown'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Type: ${entry.callType == CallType.video ? "Video" : "Voice"}'),
                      Text(
                        'Direction: ${entry.isIncoming ? "Incoming" : "Outgoing"}',
                      ),
                      Text(
                        'Status: ${entry.status.toString().split('.').last}',
                      ),
                      if (entry.durationSeconds > 0)
                        Text('Duration: ${entry.durationSeconds}s'),
                      Text(
                        'Time: ${entry.timestamp.toString().split('.')[0]}',
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

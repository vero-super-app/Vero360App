import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vero360_app/GeneralModels/call_model.dart';
import 'dart:developer' as developer;

// =============== CALL STATE PROVIDERS ===============

/// Current active call (if any)
final activeCallProvider = StateProvider<CallSession?>((ref) => null);

/// Incoming call notification
final incomingCallProvider = StateProvider<CallSession?>((ref) => null);

/// Call history entries
final callHistoryProvider = StateProvider<List<CallHistoryEntry>>((ref) => []);

/// Call duration timer (in seconds)
final callDurationProvider = StateProvider<int>((ref) => 0);

/// Microphone enabled state
final isMicrophoneEnabledProvider = StateProvider<bool>((ref) => true);

/// Camera enabled state (for video calls)
final isCameraEnabledProvider = StateProvider<bool>((ref) => true);

/// Speaker enabled state
final isSpeakerEnabledProvider = StateProvider<bool>((ref) => true);

/// Call connection quality indicator
final callQualityProvider = StateProvider<double>((ref) => 1.0); // 0-1

// =============== ACTION PROVIDERS ===============

/// Provider for call service methods
final callServiceProvider = Provider((ref) {
  return CallService(ref: ref);
});

class CallService {
  final Ref ref;

  CallService({required this.ref});

  /// Initiate a call to a user
  Future<void> initiateCall({
    required String recipientId,
    required String recipientName,
    required String? recipientAvatar,
    required String initiatorName,
    required String? initiatorAvatar,
    required CallType callType,
  }) async {
    try {
      final callSession = CallSession(
        id: 'call_${DateTime.now().millisecondsSinceEpoch}',
        initiatorId: '', // Will be set from context
        recipientId: recipientId,
        callType: callType,
        status: CallStatus.outgoing,
        initiatedAt: DateTime.now(),
        recipientName: recipientName,
        recipientAvatar: recipientAvatar,
        initiatorName: initiatorName,
        initiatorAvatar: initiatorAvatar,
      );

      ref.read(activeCallProvider.notifier).state = callSession;
    } catch (e) {
      developer.log('[CallService] Failed to initiate call: $e');
      rethrow;
    }
  }

  /// Answer incoming call
  Future<void> answerCall(CallSession call) async {
    try {
      final updated = call.copyWith(
        status: CallStatus.active,
        answeredAt: DateTime.now(),
      );
      ref.read(activeCallProvider.notifier).state = updated;
      ref.read(incomingCallProvider.notifier).state = null;
    } catch (e) {
      developer.log('[CallService] Failed to answer call: $e');
      rethrow;
    }
  }

  /// Decline incoming call
  Future<void> declineCall(CallSession call) async {
    try {
      ref.read(incomingCallProvider.notifier).state = null;
      // Update call history
      final history = _CallHistoryHelper.createEntry(
        call.copyWith(status: CallStatus.declined),
        isIncoming: true,
      );
      final currentHistory = ref.read(callHistoryProvider);
      ref.read(callHistoryProvider.notifier).state = [
        history,
        ...currentHistory
      ];
    } catch (e) {
      developer.log('[CallService] Failed to decline call: $e');
      rethrow;
    }
  }

  /// End active call
  Future<void> endCall() async {
    try {
      final activeCall = ref.read(activeCallProvider);
      if (activeCall != null) {
        final duration =
            DateTime.now().difference(activeCall.initiatedAt).inSeconds;
        final updated = activeCall.copyWith(
          status: CallStatus.ended,
          endedAt: DateTime.now(),
          durationSeconds: duration,
        );

        // Save to history
        final history =
            _CallHistoryHelper.createEntry(updated, isIncoming: false);
        final currentHistory = ref.read(callHistoryProvider);
        ref.read(callHistoryProvider.notifier).state = [
          history,
          ...currentHistory
        ];
      }

      ref.read(activeCallProvider.notifier).state = null;
      ref.read(callDurationProvider.notifier).state = 0;
    } catch (e) {
      developer.log('[CallService] Failed to end call: $e');
      rethrow;
    }
  }

  /// Toggle microphone
  Future<void> toggleMicrophone() async {
    try {
      final enabled = ref.read(isMicrophoneEnabledProvider);
      ref.read(isMicrophoneEnabledProvider.notifier).state = !enabled;
    } catch (e) {
      developer.log('[CallService] Failed to toggle microphone: $e');
    }
  }

  /// Toggle camera
  Future<void> toggleCamera() async {
    try {
      final enabled = ref.read(isCameraEnabledProvider);
      ref.read(isCameraEnabledProvider.notifier).state = !enabled;
    } catch (e) {
      developer.log('[CallService] Failed to toggle camera: $e');
    }
  }

  /// Toggle speaker
  Future<void> toggleSpeaker() async {
    try {
      final enabled = ref.read(isSpeakerEnabledProvider);
      ref.read(isSpeakerEnabledProvider.notifier).state = !enabled;
    } catch (e) {
      developer.log('[CallService] Failed to toggle speaker: $e');
    }
  }

  /// Update call duration (called by timer)
  void updateCallDuration(int seconds) {
    ref.read(callDurationProvider.notifier).state = seconds;
  }

  /// Receive incoming call notification
  void receiveIncomingCall(CallSession call) {
    ref.read(incomingCallProvider.notifier).state = call;
  }

  /// Clear incoming call
  void clearIncomingCall() {
    ref.read(incomingCallProvider.notifier).state = null;
  }

  /// Add to call history
  Future<void> addToHistory(CallHistoryEntry entry) async {
    try {
      final current = ref.read(callHistoryProvider);
      ref.read(callHistoryProvider.notifier).state = [entry, ...current];
    } catch (e) {
      developer.log('[CallService] Failed to add to history: $e');
      rethrow;
    }
  }
}

class _CallHistoryHelper {
  static CallHistoryEntry createEntry(CallSession session,
      {required bool isIncoming}) {
    return CallHistoryEntry(
      id: session.id,
      peerId: isIncoming ? session.initiatorId : session.recipientId,
      peerName: isIncoming ? session.initiatorName : session.recipientName,
      peerAvatar:
          isIncoming ? session.initiatorAvatar : session.recipientAvatar,
      callType: session.callType,
      status: session.status,
      timestamp: session.initiatedAt,
      durationSeconds: session.durationSeconds,
      isIncoming: isIncoming,
    );
  }
}

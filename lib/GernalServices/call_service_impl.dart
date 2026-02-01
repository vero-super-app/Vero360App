import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vero360_app/GeneralModels/call_model.dart';

class CallServiceImpl {
  static const String _callsCollection = 'calls';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Initiate a new call and save to Firestore
  Future<CallSession> initiateCall({
    required String initiatorId,
    required String recipientId,
    required CallType callType,
    String? initiatorName,
    String? initiatorAvatar,
    String? recipientName,
    String? recipientAvatar,
  }) async {
    try {
      final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';
      final callSession = CallSession(
        id: callId,
        initiatorId: initiatorId,
        recipientId: recipientId,
        callType: callType,
        status: CallStatus.outgoing,
        initiatedAt: DateTime.now(),
        initiatorName: initiatorName,
        initiatorAvatar: initiatorAvatar,
        recipientName: recipientName,
        recipientAvatar: recipientAvatar,
      );

      await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .set(callSession.toFirestore());

      return callSession;
    } catch (e) {
      print('[CallServiceImpl] initiateCall error: $e');
      rethrow;
    }
  }

  /// Get call by ID
  Future<CallSession?> getCall(String callId) async {
    try {
      final doc = await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .get();

      if (!doc.exists) return null;
      return CallSession.fromFirestore(doc);
    } catch (e) {
      print('[CallServiceImpl] getCall error: $e');
      rethrow;
    }
  }

  /// Update call status
  Future<void> updateCallStatus(String callId, CallStatus status) async {
    try {
      await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .update({'status': _callStatusToString(status)});
    } catch (e) {
      print('[CallServiceImpl] updateCallStatus error: $e');
      rethrow;
    }
  }

  /// Answer a call
  Future<void> answerCall(String callId) async {
    try {
      await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .update({
        'status': 'active',
        'answeredAt': Timestamp.now(),
      });
    } catch (e) {
      print('[CallServiceImpl] answerCall error: $e');
      rethrow;
    }
  }

  /// Decline a call
  Future<void> declineCall(String callId) async {
    try {
      await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .update({
        'status': 'declined',
        'endedAt': Timestamp.now(),
      });
    } catch (e) {
      print('[CallServiceImpl] declineCall error: $e');
      rethrow;
    }
  }

  /// End a call
  Future<void> endCall(String callId, int durationSeconds) async {
    try {
      await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .update({
        'status': 'ended',
        'endedAt': Timestamp.now(),
        'durationSeconds': durationSeconds,
      });
    } catch (e) {
      print('[CallServiceImpl] endCall error: $e');
      rethrow;
    }
  }

  /// Get call history for a user (limit 50 most recent)
  Future<List<CallHistoryEntry>> getCallHistory(
    String userId,
    {int limit = 50}
  ) async {
    try {
      final query1 = await _firestore
          .collection(_callsCollection)
          .where('initiatorId', isEqualTo: userId)
          .orderBy('initiatedAt', descending: true)
          .limit(limit)
          .get();

      final query2 = await _firestore
          .collection(_callsCollection)
          .where('recipientId', isEqualTo: userId)
          .orderBy('initiatedAt', descending: true)
          .limit(limit)
          .get();

      final sessions = [
        ...query1.docs.map((doc) => CallSession.fromFirestore(doc)),
        ...query2.docs.map((doc) => CallSession.fromFirestore(doc)),
      ];

      // Sort by date descending
      sessions.sort((a, b) => b.initiatedAt.compareTo(a.initiatedAt));

      // Convert to history entries and limit to top 50
      return sessions
          .take(limit)
          .map((session) =>
          CallHistoryEntry.fromCallSession(session, userId))
          .toList();
    } catch (e) {
      print('[CallServiceImpl] getCallHistory error: $e');
      rethrow;
    }
  }

  /// Stream of incoming calls for a user
  Stream<CallSession> incomingCallsStream(String userId) {
    return _firestore
        .collection(_callsCollection)
        .where('recipientId', isEqualTo: userId)
        .where('status', isEqualTo: 'incoming')
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => CallSession.fromFirestore(doc))
        .toList())
        .expand((list) => list);
  }

  /// Stream of active calls for a user
  Stream<CallSession> activeCallsStream(String userId) {
    return _firestore
        .collection(_callsCollection)
        .where('initiatorId', isEqualTo: userId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => CallSession.fromFirestore(doc))
        .toList())
        .expand((list) => list);
  }

  /// Clear call history for a user
  Future<void> clearCallHistory(String userId) async {
    try {
      final batch = _firestore.batch();

      // Get all calls for this user
      final query1 = await _firestore
          .collection(_callsCollection)
          .where('initiatorId', isEqualTo: userId)
          .get();

      final query2 = await _firestore
          .collection(_callsCollection)
          .where('recipientId', isEqualTo: userId)
          .get();

      // Delete them
      for (final doc in query1.docs) {
        batch.delete(doc.reference);
      }
      for (final doc in query2.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    } catch (e) {
      print('[CallServiceImpl] clearCallHistory error: $e');
      rethrow;
    }
  }

  String _callStatusToString(CallStatus status) {
    return status.toString().split('.').last;
  }
}

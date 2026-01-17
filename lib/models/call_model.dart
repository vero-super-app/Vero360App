import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { voice, video }

enum CallStatus { incoming, outgoing, active, ended, missed, declined, failed }

class CallSession {
  final String id;
  final String initiatorId;
  final String recipientId;
  final CallType callType;
  final CallStatus status;
  final DateTime initiatedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final String? initiatorName;
  final String? initiatorAvatar;
  final String? recipientName;
  final String? recipientAvatar;

  CallSession({
    required this.id,
    required this.initiatorId,
    required this.recipientId,
    required this.callType,
    required this.status,
    required this.initiatedAt,
    this.answeredAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.initiatorName,
    this.initiatorAvatar,
    this.recipientName,
    this.recipientAvatar,
  });

  factory CallSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CallSession(
      id: doc.id,
      initiatorId: data['initiatorId'] ?? '',
      recipientId: data['recipientId'] ?? '',
      callType: (data['callType'] ?? 'voice') == 'video'
          ? CallType.video
          : CallType.voice,
      status: _parseCallStatus(data['status'] ?? 'incoming'),
      initiatedAt: (data['initiatedAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      answeredAt: (data['answeredAt'] as Timestamp?)?.toDate(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
      durationSeconds: data['durationSeconds'] ?? 0,
      initiatorName: data['initiatorName'],
      initiatorAvatar: data['initiatorAvatar'],
      recipientName: data['recipientName'],
      recipientAvatar: data['recipientAvatar'],
    );
  }

  Map<String, dynamic> toFirestore() => {
    'initiatorId': initiatorId,
    'recipientId': recipientId,
    'callType': callType == CallType.video ? 'video' : 'voice',
    'status': _callStatusToString(status),
    'initiatedAt': Timestamp.fromDate(initiatedAt),
    'answeredAt': answeredAt != null ? Timestamp.fromDate(answeredAt!) : null,
    'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
    'durationSeconds': durationSeconds,
    'initiatorName': initiatorName,
    'initiatorAvatar': initiatorAvatar,
    'recipientName': recipientName,
    'recipientAvatar': recipientAvatar,
  };

  CallSession copyWith({
    String? id,
    String? initiatorId,
    String? recipientId,
    CallType? callType,
    CallStatus? status,
    DateTime? initiatedAt,
    DateTime? answeredAt,
    DateTime? endedAt,
    int? durationSeconds,
    String? initiatorName,
    String? initiatorAvatar,
    String? recipientName,
    String? recipientAvatar,
  }) {
    return CallSession(
      id: id ?? this.id,
      initiatorId: initiatorId ?? this.initiatorId,
      recipientId: recipientId ?? this.recipientId,
      callType: callType ?? this.callType,
      status: status ?? this.status,
      initiatedAt: initiatedAt ?? this.initiatedAt,
      answeredAt: answeredAt ?? this.answeredAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      initiatorName: initiatorName ?? this.initiatorName,
      initiatorAvatar: initiatorAvatar ?? this.initiatorAvatar,
      recipientName: recipientName ?? this.recipientName,
      recipientAvatar: recipientAvatar ?? this.recipientAvatar,
    );
  }
}

CallStatus _parseCallStatus(String status) {
  switch (status.toLowerCase()) {
    case 'incoming':
      return CallStatus.incoming;
    case 'outgoing':
      return CallStatus.outgoing;
    case 'active':
      return CallStatus.active;
    case 'ended':
      return CallStatus.ended;
    case 'missed':
      return CallStatus.missed;
    case 'declined':
      return CallStatus.declined;
    case 'failed':
      return CallStatus.failed;
    default:
      return CallStatus.incoming;
  }
}

String _callStatusToString(CallStatus status) {
  return status.toString().split('.').last;
}

class CallHistoryEntry {
  final String id;
  final String peerId;
  final String? peerName;
  final String? peerAvatar;
  final CallType callType;
  final CallStatus status;
  final DateTime timestamp;
  final int durationSeconds;
  final bool isIncoming;

  CallHistoryEntry({
    required this.id,
    required this.peerId,
    this.peerName,
    this.peerAvatar,
    required this.callType,
    required this.status,
    required this.timestamp,
    required this.durationSeconds,
    required this.isIncoming,
  });

  factory CallHistoryEntry.fromCallSession(
    CallSession session,
    String currentUserId,
  ) {
    final isIncoming = session.recipientId == currentUserId;
    return CallHistoryEntry(
      id: session.id,
      peerId: isIncoming ? session.initiatorId : session.recipientId,
      peerName:
          isIncoming ? session.initiatorName : session.recipientName,
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

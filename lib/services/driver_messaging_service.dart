import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Message between driver and passenger
class DriverMessage {
  final String id;
  final String rideId;
  final String senderId;
  final String senderType; // 'driver' or 'passenger'
  final String senderName;
  final String? senderAvatar;
  final String message;
  final DateTime sentAt;
  final bool isRead;
  final String messageType; // 'text', 'status_update', 'system'

  DriverMessage({
    required this.id,
    required this.rideId,
    required this.senderId,
    required this.senderType,
    required this.senderName,
    this.senderAvatar,
    required this.message,
    required this.sentAt,
    this.isRead = false,
    this.messageType = 'text',
  });

  Map<String, dynamic> toMap() {
    return {
      'rideId': rideId,
      'senderId': senderId,
      'senderType': senderType,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'message': message,
      'sentAt': sentAt.toIso8601String(),
      'isRead': isRead,
      'messageType': messageType,
    };
  }

  factory DriverMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final sentAt = data['sentAt'] is String
        ? DateTime.parse(data['sentAt'])
        : (data['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    return DriverMessage(
      id: doc.id,
      rideId: data['rideId'] ?? '',
      senderId: data['senderId'] ?? '',
      senderType: data['senderType'] ?? 'passenger',
      senderName: data['senderName'] ?? 'Unknown',
      senderAvatar: data['senderAvatar'],
      message: data['message'] ?? '',
      sentAt: sentAt,
      isRead: data['isRead'] ?? false,
      messageType: data['messageType'] ?? 'text',
    );
  }
}

/// Ride conversation thread
class DriverRideConversation {
  final String rideId;
  final String passengerId;
  final String driverId;
  final String passengerName;
  final String driverName;
  final String? passengerAvatar;
  final String? driverAvatar;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;

  DriverRideConversation({
    required this.rideId,
    required this.passengerId,
    required this.driverId,
    required this.passengerName,
    required this.driverName,
    this.passengerAvatar,
    this.driverAvatar,
    required this.lastMessage,
    required this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory DriverRideConversation.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final lastMessageAt = data['lastMessageAt'] is String
        ? DateTime.parse(data['lastMessageAt'])
        : (data['lastMessageAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    return DriverRideConversation(
      rideId: doc.id,
      passengerId: data['passengerId'] ?? '',
      driverId: data['driverId'] ?? '',
      passengerName: data['passengerName'] ?? 'Passenger',
      driverName: data['driverName'] ?? 'Driver',
      passengerAvatar: data['passengerAvatar'],
      driverAvatar: data['driverAvatar'],
      lastMessage: data['lastMessage'] ?? '',
      lastMessageAt: lastMessageAt,
      unreadCount: data['unreadCount'] ?? 0,
    );
  }
}

class DriverMessagingService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get or create a ride conversation thread
  static Future<void> ensureRideThread({
    required String rideId,
    required String passengerId,
    required String driverId,
    required String passengerName,
    required String driverName,
    String? passengerAvatar,
    String? driverAvatar,
  }) async {
    try {
      final threadRef = _db.collection('ride_messages').doc(rideId);

      await threadRef.set({
        'rideId': rideId,
        'passengerId': passengerId,
        'driverId': driverId,
        'passengerName': passengerName,
        'driverName': driverName,
        'passengerAvatar': passengerAvatar ?? '',
        'driverAvatar': driverAvatar ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': 'Conversation started',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': driverId,
        'unreadCount': 0,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error creating ride thread: $e');
      rethrow;
    }
  }

  /// Send a message in a ride conversation
  static Future<void> sendMessage({
    required String rideId,
    required String message,
    String? senderName,
    String? senderAvatar,
    String messageType = 'text',
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) throw Exception('Not authenticated');

      final messagesRef = _db.collection('ride_messages').doc(rideId);
      final messageRef = messagesRef.collection('messages').doc();

      await _db.runTransaction((transaction) async {
        // Add message
        transaction.set(messageRef, {
          'rideId': rideId,
          'senderId': userId,
          'senderType': 'driver', // Driver-specific
          'senderName': senderName ?? 'Driver',
          'senderAvatar': senderAvatar,
          'message': message,
          'sentAt': FieldValue.serverTimestamp(),
          'isRead': false,
          'messageType': messageType,
        });

        // Update thread metadata
        transaction.update(messagesRef, {
          'lastMessage': message,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastSenderId': userId,
        });
      });
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  /// Get messages for a ride
  static Stream<List<DriverMessage>> getMessagesStream(String rideId) {
    return _db
        .collection('ride_messages')
        .doc(rideId)
        .collection('messages')
        .orderBy('sentAt', descending: false)
        .snapshots()
        .map((qs) {
      return qs.docs.map((doc) => DriverMessage.fromDoc(doc)).toList();
    });
  }

  /// Mark messages as read
  static Future<void> markMessagesAsRead(String rideId) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      final batch = _db.batch();
      final messagesRef = _db
          .collection('ride_messages')
          .doc(rideId)
          .collection('messages')
          .where('senderType', isEqualTo: 'passenger')
          .where('isRead', isEqualTo: false);

      final snapshots = await messagesRef.get();

      for (final doc in snapshots.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  /// Get unread message count for a conversation
  static Future<int> getUnreadCount(String rideId) async {
    try {
      final messagesRef = _db
          .collection('ride_messages')
          .doc(rideId)
          .collection('messages')
          .where('senderType', isEqualTo: 'passenger')
          .where('isRead', isEqualTo: false);

      final snapshot = await messagesRef.count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }

  /// Send a system status message (e.g., "Driver arrived")
  static Future<void> sendSystemMessage({
    required String rideId,
    required String message,
  }) async {
    try {
      final messagesRef = _db.collection('ride_messages').doc(rideId);
      final messageRef = messagesRef.collection('messages').doc();

      await _db.runTransaction((transaction) async {
        transaction.set(messageRef, {
          'rideId': rideId,
          'senderId': 'system',
          'senderType': 'system',
          'senderName': 'System',
          'message': message,
          'sentAt': FieldValue.serverTimestamp(),
          'isRead': false,
          'messageType': 'system',
        });

        transaction.update(messagesRef, {
          'lastMessage': message,
          'lastMessageAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      print('Error sending system message: $e');
      rethrow;
    }
  }

  /// Get ride conversation details
  static Future<DriverRideConversation?> getRideConversation(
    String rideId,
  ) async {
    try {
      final doc = await _db.collection('ride_messages').doc(rideId).get();
      if (doc.exists) {
        return DriverRideConversation.fromDoc(doc);
      }
      return null;
    } catch (e) {
      print('Error getting ride conversation: $e');
      return null;
    }
  }

  /// Stream for ride conversation updates
  static Stream<DriverRideConversation?> getRideConversationStream(
    String rideId,
  ) {
    return _db
        .collection('ride_messages')
        .doc(rideId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists) {
        return DriverRideConversation.fromDoc(snapshot);
      }
      return null;
    });
  }

  /// Get all active conversations for a driver
  static Stream<List<DriverRideConversation>> getDriverConversationsStream(
    String driverId,
  ) {
    return _db
        .collection('ride_messages')
        .where('driverId', isEqualTo: driverId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((qs) {
      return qs.docs.map((doc) => DriverRideConversation.fromDoc(doc)).toList();
    });
  }

  /// Delete a conversation (archive it instead)
  static Future<void> archiveConversation(String rideId) async {
    try {
      await _db.collection('ride_messages').doc(rideId).update({
        'archived': true,
        'archivedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error archiving conversation: $e');
      rethrow;
    }
  }
}

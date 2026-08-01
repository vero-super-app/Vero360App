import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vero360_app/config/api_config.dart';

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

  factory DriverMessage.fromMap(Map<String, dynamic> map) {
    final sentAtStr = map['sentAt'] as String?;
    final sentAt = sentAtStr != null 
        ? DateTime.parse(sentAtStr)
        : DateTime.now();

    return DriverMessage(
      id: map['id'] ?? '',
      rideId: map['rideId'] ?? '',
      senderId: map['senderId'] ?? '',
      senderType: map['senderType'] ?? 'passenger',
      senderName: map['senderName'] ?? 'Unknown',
      senderAvatar: map['senderAvatar'],
      message: map['message'] ?? '',
      sentAt: sentAt,
      isRead: map['isRead'] ?? false,
      messageType: map['messageType'] ?? 'text',
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

  factory DriverRideConversation.fromMap(Map<String, dynamic> map) {
    final lastMessageAtStr = map['lastMessageAt'] as String?;
    final lastMessageAt = lastMessageAtStr != null 
        ? DateTime.parse(lastMessageAtStr)
        : DateTime.now();

    return DriverRideConversation(
      rideId: map['rideId'] ?? '',
      passengerId: map['passengerId'] ?? '',
      driverId: map['driverId'] ?? '',
      passengerName: map['passengerName'] ?? 'Passenger',
      driverName: map['driverName'] ?? 'Driver',
      passengerAvatar: map['passengerAvatar'],
      driverAvatar: map['driverAvatar'],
      lastMessage: map['lastMessage'] ?? '',
      lastMessageAt: lastMessageAt,
      unreadCount: map['unreadCount'] ?? 0,
    );
  }
}

class DriverMessagingService {
  static const String _baseUrl = '/api/messages';

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
      final response = await http.post(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId/thread'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'rideId': rideId,
          'passengerId': passengerId,
          'driverId': driverId,
          'passengerName': passengerName,
          'driverName': driverName,
          'passengerAvatar': passengerAvatar,
          'driverAvatar': driverAvatar,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to create ride thread: ${response.statusCode}');
      }
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
      final response = await http.post(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId/messages'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'message': message,
          'senderName': senderName ?? 'Driver',
          'senderAvatar': senderAvatar,
          'messageType': messageType,
          'senderType': 'driver',
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  /// Get messages for a ride (one-time fetch)
  static Future<List<DriverMessage>> getMessages(String rideId) async {
    try {
      final response = await http.get(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId/messages'),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final messages = decoded is List 
            ? decoded.cast<Map<String, dynamic>>()
            : (decoded['messages'] is List 
                ? (decoded['messages'] as List).cast<Map<String, dynamic>>()
                : <Map<String, dynamic>>[]);
        
        return messages.map((msg) => DriverMessage.fromMap(msg)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching messages: $e');
      return [];
    }
  }

  /// Mark messages as read
  static Future<void> markMessagesAsRead(String rideId) async {
    try {
      final response = await http.patch(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId/mark-read'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to mark messages as read: ${response.statusCode}');
      }
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  /// Get unread message count for a conversation
  static Future<int> getUnreadCount(String rideId) async {
    try {
      final response = await http.get(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId/unread-count'),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['unreadCount'] ?? 0;
      }
      return 0;
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
      final response = await http.post(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId/system-message'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'message': message,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to send system message: ${response.statusCode}');
      }
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
      final response = await http.get(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId'),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return DriverRideConversation.fromMap(decoded);
      }
      return null;
    } catch (e) {
      print('Error getting ride conversation: $e');
      return null;
    }
  }

  /// Get all active conversations for a driver
  static Future<List<DriverRideConversation>> getDriverConversations(
    String driverId,
  ) async {
    try {
      final response = await http.get(
        ApiConfig.endpoint('$_baseUrl/drivers/$driverId/conversations'),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final conversations = decoded is List 
            ? decoded.cast<Map<String, dynamic>>()
            : (decoded['conversations'] is List 
                ? (decoded['conversations'] as List).cast<Map<String, dynamic>>()
                : <Map<String, dynamic>>[]);
        
        return conversations.map((conv) => DriverRideConversation.fromMap(conv)).toList();
      }
      return [];
    } catch (e) {
      print('Error getting driver conversations: $e');
      return [];
    }
  }

  /// Archive a conversation
  static Future<void> archiveConversation(String rideId) async {
    try {
      final response = await http.patch(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId/archive'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to archive conversation: ${response.statusCode}');
      }
    } catch (e) {
      print('Error archiving conversation: $e');
      rethrow;
    }
  }
}

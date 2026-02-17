import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';

class BackendChatThread {
  final String id;
  final String type; // 'direct' or 'group'
  final String? name;
  final String? description;
  final String? avatarUrl;
  final bool isArchived;
  final int participantCount;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatParticipant> participants;

  BackendChatThread({
    required this.id,
    required this.type,
    this.name,
    this.description,
    this.avatarUrl,
    this.isArchived = false,
    required this.participantCount,
    this.lastMessageAt,
    required this.unreadCount,
    required this.createdAt,
    required this.updatedAt,
    required this.participants,
  });

  String otherId(String me) {
    if (participants.isEmpty) return me;
    final others = participants.where((p) => p.id.toString() != me).toList();
    return others.isNotEmpty ? others.first.id.toString() : me;
  }

  factory BackendChatThread.fromJson(Map<String, dynamic> json) {
    return BackendChatThread(
      id: json['id'] ?? '',
      type: json['type'] ?? 'direct',
      name: json['name'],
      description: json['description'],
      avatarUrl: json['avatarUrl'],
      isArchived: json['isArchived'] ?? false,
      participantCount: json['participantCount'] ?? 0,
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.parse(json['lastMessageAt'])
          : null,
      unreadCount: json['unreadCount'] ?? 0,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
      participants: (json['participants'] as List?)
              ?.map((p) => ChatParticipant.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class BackendChatMessage {
  final String id;
  final String chatId;
  final int senderId;
  final String? content;
  final String type; // 'text', 'image', 'video', 'audio', etc.
  final String status; // 'sent', 'delivered', 'read', 'failed'
  final DateTime createdAt;
  final DateTime? readAt;

  BackendChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.content,
    required this.type,
    required this.status,
    required this.createdAt,
    this.readAt,
  });

  bool isMine(int myUserId) => senderId == myUserId;

  factory BackendChatMessage.fromJson(Map<String, dynamic> json) {
    return BackendChatMessage(
      id: json['id'] ?? '',
      chatId: json['chatId'] ?? '',
      senderId: json['senderId'] ?? 0,
      content: json['content'],
      type: json['type'] ?? 'text',
      status: json['status'] ?? 'sent',
      createdAt: DateTime.parse(
          json['createdAt'] ?? DateTime.now().toIso8601String()),
      readAt: json['readAt'] != null ? DateTime.parse(json['readAt']) : null,
    );
  }
}

class ChatParticipant {
  final int id;
  final String name;
  final String email;
  final String? profilePicture;

  ChatParticipant({
    required this.id,
    required this.name,
    required this.email,
    this.profilePicture,
  });

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Unknown',
      email: json['email'] ?? '',
      profilePicture: json['profilepicture'] ?? json['profilePicture'],
    );
  }
}

class BackendChatService {
  /// Uses ApiConfig for base URL (supports dart-define, ngrok, etc.)
  /// Builds: {ApiConfig.prod}/vero/api/v1
  static String get _baseUrl => '${ApiConfig.prod}/vero/api/v1';
  
  static String? _authToken;
  static int? _userId;

  static Future<void> ensureAuth() async {
    // Ensure ApiConfig is initialized
    await ApiConfig.init();
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated with Firebase');
    }

    _authToken = await user.getIdToken();
    
    if (_authToken == null || _authToken!.isEmpty) {
      throw Exception('Failed to get Firebase ID token');
    }

    // Get userId from SharedPreferences, or from JWT, or from GET /users/me
    final sp = await SharedPreferences.getInstance();
    int? userId = sp.getInt('userId') ?? sp.getInt('user_id');
    if (userId == null) {
      userId = await AuthStorage.userIdFromToken();
      if (userId != null) {
        await sp.setInt('userId', userId);
        await sp.setInt('user_id', userId);
      }
    }
    if (userId == null && _authToken != null && _authToken!.isNotEmpty) {
      // Firebase JWT has string sub (UID); fetch numeric id from backend
      try {
        final meUrl = ApiConfig.endpoint('/users/me');
        final response = await http.get(
          meUrl,
          headers: {'Authorization': _authHeader},
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>?;
          if (json != null) {
            final data = json['data'] is Map<String, dynamic>
                ? json['data'] as Map<String, dynamic>
                : json;
            final rawId = data['id'] ?? data['userId'];
            if (rawId != null) {
              userId = rawId is int ? rawId : int.tryParse(rawId.toString());
              if (userId != null) {
                await sp.setInt('userId', userId);
                await sp.setInt('user_id', userId);
              }
            }
          }
        }
      } catch (e) {
        print('[BackendChatService] Failed to fetch /users/me for userId: $e');
      }
    }
    if (userId == null) {
      print('[BackendChatService] WARNING: userId not found in SharedPreferences');
      print('[BackendChatService] Make sure to call: SharedPreferences.getInstance().setInt("userId", <numeric_id>)');
      print('[BackendChatService] after user login with your backend');
      throw Exception(
        'User ID not set in SharedPreferences. '
        'Backend must provide numeric userId after authentication.'
      );
    }

    _userId = userId;
  }

  static Future<int> getUserId() async {
    await ensureAuth();
    return _userId!;
  }

  static String get _authHeader => 'Bearer $_authToken';

  /// Get user's chat threads
  static Future<List<BackendChatThread>> getThreads({
    int page = 1,
    int pageSize = 20,
  }) async {
    await ensureAuth();

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/chats?page=$page&pageSize=$pageSize'),
        headers: {'Authorization': _authHeader},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = json['data'] as List? ?? [];
        return data
            .map((t) => BackendChatThread.fromJson(t as Map<String, dynamic>))
            .toList();
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized - please log in again');
      } else {
        throw Exception('Failed to fetch chats: ${response.statusCode}');
      }
    } catch (e) {
      print('[BackendChatService] Error fetching threads: $e');
      rethrow;
    }
  }

  /// Stream of user's chat threads (polling-based)
  static Stream<List<BackendChatThread>> threadsStream({
    Duration pollInterval = const Duration(seconds: 5),
  }) {
    return Stream.periodic(pollInterval, (_) async {
      return await getThreads();
    }).asyncMap((future) => future).handleError((error) {
      print('[BackendChatService] Stream error: $error');
    });
  }

  /// Get a specific chat
  static Future<BackendChatThread> getChat(String chatId) async {
    await ensureAuth();

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/chats/$chatId'),
        headers: {'Authorization': _authHeader},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return BackendChatThread.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      } else {
        throw Exception('Failed to fetch chat: ${response.statusCode}');
      }
    } catch (e) {
      print('[BackendChatService] Error fetching chat: $e');
      rethrow;
    }
  }

  /// Get messages in a chat
  static Future<List<BackendChatMessage>> getMessages(
    String chatId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    await ensureAuth();

    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/chats/$chatId/messages?page=$page&pageSize=$pageSize'),
        headers: {'Authorization': _authHeader},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = json['data'] as List? ?? [];
        return data
            .map((m) => BackendChatMessage.fromJson(m as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to fetch messages: ${response.statusCode}');
      }
    } catch (e) {
      print('[BackendChatService] Error fetching messages: $e');
      rethrow;
    }
  }

  /// Send a message
  static Future<BackendChatMessage> sendMessage({
    required String chatId,
    required String content,
    String type = 'text',
  }) async {
    await ensureAuth();

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chats/$chatId/messages'),
        headers: {
          'Authorization': _authHeader,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'content': content,
          'type': type,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        return BackendChatMessage.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      } else {
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } catch (e) {
      print('[BackendChatService] Error sending message: $e');
      rethrow;
    }
  }

  /// Edit a message
  static Future<BackendChatMessage> editMessage({
    required String chatId,
    required String messageId,
    required String newContent,
  }) async {
    await ensureAuth();

    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/chats/$chatId/messages/$messageId'),
        headers: {
          'Authorization': _authHeader,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'content': newContent}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return BackendChatMessage.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      } else {
        throw Exception('Failed to edit message: ${response.statusCode}');
      }
    } catch (e) {
      print('[BackendChatService] Error editing message: $e');
      rethrow;
    }
  }

  /// Delete a message
  static Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    await ensureAuth();

    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/chats/$chatId/messages/$messageId'),
        headers: {'Authorization': _authHeader},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Failed to delete message: ${response.statusCode}');
      }
    } catch (e) {
      print('[BackendChatService] Error deleting message: $e');
      rethrow;
    }
  }

  /// Create or get direct chat with a user
  static Future<BackendChatThread> ensureChat({
    required int peerUserId,
    String? peerName,
    String? peerAvatar,
  }) async {
    await ensureAuth();

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chats'),
        headers: {
          'Authorization': _authHeader,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'type': 'direct',
          'participantIds': [_userId, peerUserId],
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        return BackendChatThread.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      } else {
        throw Exception('Failed to create chat: ${response.statusCode}');
      }
    } catch (e) {
      print('[BackendChatService] Error ensuring chat: $e');
      rethrow;
    }
  }

  /// Mark messages as read
  static Future<void> markRead({
    required String chatId,
    required List<String> messageIds,
  }) async {
    await ensureAuth();

    try {
      await http.patch(
        Uri.parse('$_baseUrl/chats/$chatId/messages/read'),
        headers: {
          'Authorization': _authHeader,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'messageIds': messageIds}),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      print('[BackendChatService] Error marking as read: $e');
      rethrow;
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vero360_app/GeneralModels/messaging_models.dart';

/// Service for searching messages and chats
class SearchService {
  static const String _messagesCollection = 'messages';
  static const String _chatsCollection = 'chats';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Search messages by keyword
  Future<List<Message>> searchMessages({
    required String keyword,
    String? chatId,
    String? userId,
    int limit = 50,
  }) async {
    try {
      Query query = _firestore.collection(_messagesCollection);

      // Filter by chat if specified
      if (chatId != null) {
        query = query.where('chatId', isEqualTo: chatId);
      }

      // Filter by user if specified
      if (userId != null) {
        query = query.where('senderId', isEqualTo: userId);
      }

      // Order by timestamp and limit
      query = query
          .orderBy('createdAt', descending: true)
          .limit(limit);

      final docs = await query.get();

      // Filter by keyword in content (client-side)
      return docs.docs
          .map((doc) {
            final msg = MessageFactory.fromFirestore(doc);
            return msg;
          })
          .where((msg) =>
              msg.content.toLowerCase().contains(keyword.toLowerCase()))
          .toList();
    } catch (e) {
      print('[SearchService] searchMessages error: $e');
      rethrow;
    }
  }

  /// Search chats by name or participants
  Future<List<Chat>> searchChats({
    required String keyword,
    required String userId,
    int limit = 20,
  }) async {
    try {
      // Search by chat name
      final byName = await _firestore
          .collection(_chatsCollection)
          .where('participants', arrayContains: userId)
          .get();

      final results = byName.docs
          .map((doc) => Chat.fromFirestore(doc))
          .where((chat) =>
              (chat.name?.toLowerCase().contains(keyword.toLowerCase()) ?? false) ||
              (chat.description?.toLowerCase().contains(keyword.toLowerCase()) ?? false))
          .take(limit)
          .toList();

      return results;
    } catch (e) {
      print('[SearchService] searchChats error: $e');
      rethrow;
    }
  }

  /// Get recent searches for a user
  Future<List<String>> getRecentSearches(String userId, {int limit = 10}) async {
    try {
      final doc = await _firestore
          .collection('user_preferences')
          .doc(userId)
          .get();

      if (!doc.exists) return [];

      final searches = (doc.data()?['recentSearches'] as List?)
              ?.cast<String>()
              .take(limit)
              .toList() ??
          [];

      return searches;
    } catch (e) {
      print('[SearchService] getRecentSearches error: $e');
      return [];
    }
  }

  /// Save search to recent searches
  Future<void> saveSearch(String userId, String searchQuery) async {
    try {
      final userPrefRef = _firestore.collection('user_preferences').doc(userId);

      await userPrefRef.update({
        'recentSearches': FieldValue.arrayUnion([searchQuery]),
        'lastSearch': Timestamp.now(),
      }).catchError((_) {
        // Document doesn't exist, create it
        return userPrefRef.set({
          'userId': userId,
          'recentSearches': [searchQuery],
          'lastSearch': Timestamp.now(),
        });
      });
    } catch (e) {
      print('[SearchService] saveSearch error: $e');
    }
  }

  /// Clear recent searches for a user
  Future<void> clearRecentSearches(String userId) async {
    try {
      await _firestore
          .collection('user_preferences')
          .doc(userId)
          .update({
        'recentSearches': [],
      });
    } catch (e) {
      print('[SearchService] clearRecentSearches error: $e');
    }
  }

  /// Search messages by timestamp range
  Future<List<Message>> searchMessagesByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    String? chatId,
    int limit = 50,
  }) async {
    try {
      Query query = _firestore.collection(_messagesCollection);

      if (chatId != null) {
        query = query.where('chatId', isEqualTo: chatId);
      }

      query = query
          .where('createdAt', isGreaterThanOrEqualTo: startDate)
          .where('createdAt', isLessThanOrEqualTo: endDate)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      final docs = await query.get();
      return docs.docs
          .map((doc) {
            final msg = MessageFactory.fromFirestore(doc);
            return msg;
          })
          .toList();
    } catch (e) {
      print('[SearchService] searchMessagesByDateRange error: $e');
      rethrow;
    }
  }

  /// Search messages by sender
  Future<List<Message>> searchMessagesBySender({
    required String senderId,
    String? chatId,
    int limit = 50,
  }) async {
    try {
      Query query = _firestore
          .collection(_messagesCollection)
          .where('senderId', isEqualTo: senderId);

      if (chatId != null) {
        query = query.where('chatId', isEqualTo: chatId);
      }

      query = query
          .orderBy('createdAt', descending: true)
          .limit(limit);

      final docs = await query.get();
      return docs.docs
          .map((doc) {
            final msg = MessageFactory.fromFirestore(doc);
            return msg;
          })
          .toList();
    } catch (e) {
      print('[SearchService] searchMessagesBySender error: $e');
      rethrow;
    }
  }

  /// Search messages with attachments
  Future<List<Message>> searchMessagesWithAttachments({
    required String chatId,
    int limit = 50,
  }) async {
    try {
      final docs = await _firestore
          .collection(_messagesCollection)
          .where('chatId', isEqualTo: chatId)
          .where('hasAttachments', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return docs.docs
          .map((doc) {
            final msg = MessageFactory.fromFirestore(doc);
            return msg;
          })
          .toList();
    } catch (e) {
      print('[SearchService] searchMessagesWithAttachments error: $e');
      rethrow;
    }
  }
}

/// Search result model
class SearchResult {
  final String id;
  final String type; // 'message' or 'chat'
  final String title;
  final String? subtitle;
  final String? preview;
  final DateTime timestamp;
  final String? userId;
  final String? chatId;

  SearchResult({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.preview,
    required this.timestamp,
    this.userId,
    this.chatId,
  });
}

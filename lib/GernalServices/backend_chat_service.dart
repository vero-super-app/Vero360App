import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GeneralModels/chat_product_context.dart';
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
  final String? lastMessagePreview;
  final ChatProductContext? lastProductTag;

  BackendChatThread({
    required this.id,
    required this.type,
    this.name,
    this.description,
    this.avatarUrl,
    this.isArchived = false,
    required this.participantCount,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.lastProductTag,
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
      participantCount: (json['participantCount'] as int?) ??
          (json['participants'] as List?)?.length ??
          0,
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.parse(json['lastMessageAt'].toString())
          : (json['updatedAt'] != null
              ? DateTime.parse(json['updatedAt'].toString())
              : null),
      unreadCount: (json['unreadCount'] as int?) ?? 0,
      lastMessagePreview: json['lastMessagePreview']?.toString(),
      lastProductTag: json['lastProductTag'] is Map
          ? ChatProductContext.fromTagMap(
              Map<String, dynamic>.from(json['lastProductTag'] as Map),
            )
          : null,
      createdAt: DateTime.parse(
          json['createdAt']?.toString() ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(
          json['updatedAt']?.toString() ?? DateTime.now().toIso8601String()),
      participants: (json['participants'] as List?)
              ?.map((p) => ChatParticipant.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  BackendChatThread copyWith({
    String? id,
    String? type,
    String? name,
    String? description,
    String? avatarUrl,
    bool? isArchived,
    int? participantCount,
    DateTime? lastMessageAt,
    int? unreadCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatParticipant>? participants,
    String? lastMessagePreview,
    ChatProductContext? lastProductTag,
  }) {
    return BackendChatThread(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isArchived: isArchived ?? this.isArchived,
      participantCount: participantCount ?? this.participantCount,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      participants: participants ?? this.participants,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastProductTag: lastProductTag ?? this.lastProductTag,
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
  final DateTime? deliveredAt;
  final List<Map<String, dynamic>>? attachments;
  final List<Map<String, dynamic>>? tags;
  final Map<String, dynamic>? sender;
  final String? clientMessageId;

  BackendChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.content,
    required this.type,
    required this.status,
    required this.createdAt,
    this.readAt,
    this.deliveredAt,
    this.attachments,
    this.tags,
    this.sender,
    this.clientMessageId,
  });

  bool isMine(int myUserId) => senderId == myUserId;

  factory BackendChatMessage.fromJson(Map<String, dynamic> json) {
    return BackendChatMessage(
      id: json['id'] ?? '',
      chatId: json['chatId'] ?? '',
      senderId: (json['senderId'] is int)
          ? json['senderId']
          : int.tryParse(json['senderId'].toString()) ?? 0,
      content: json['content'],
      type: json['type'] ?? 'text',
      status: json['status'] ?? 'sent',
      createdAt:
          DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      readAt: json['readAt'] != null ? DateTime.parse(json['readAt']) : null,
      deliveredAt: json['deliveredAt'] != null
          ? DateTime.parse(json['deliveredAt'])
          : null,
      attachments: json['attachments'] != null
          ? List<Map<String, dynamic>>.from(json['attachments'] as List)
          : null,
      tags: json['tags'] != null
          ? List<Map<String, dynamic>>.from(json['tags'] as List)
          : null,
      sender: json['sender'] is Map
          ? Map<String, dynamic>.from(json['sender'] as Map)
          : null,
      clientMessageId: json['clientMessageId']?.toString(),
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
  static String? _cachedFirebaseUid;
  static DateTime? _tokenFetchedAt;
  static const Duration _tokenTtl = Duration(minutes: 50);

  // Stream controller for threads refresh
  static final _threadsRefreshController = StreamController<void>.broadcast();
  static Stream<void> get _threadsRefresh => _threadsRefreshController.stream;

  static final _threadsLiveController =
      StreamController<List<BackendChatThread>>.broadcast();
  static List<BackendChatThread> _cachedThreads = [];
  static bool _threadsWatchReady = false;
  static Timer? _threadsFallbackPollTimer;
  static String? _activeChatId;
  static bool _wsConnected = false;

  /// Chat currently open in [MessagePageBackendApi] (suppresses unread bump).
  static void setActiveChatId(String? chatId) => _activeChatId = chatId;

  static void notifyWsConnected(bool connected) {
    _wsConnected = connected;
    if (connected) {
      _threadsFallbackPollTimer?.cancel();
      _threadsFallbackPollTimer = null;
    } else {
      _ensureThreadsFallbackPoll();
    }
  }

  /// Apply a real-time message to the in-memory thread list.
  static void notifyRealtimeMessage(BackendChatMessage message) {
    if (!_threadsWatchReady || _cachedThreads.isEmpty) {
      refreshThreads();
      return;
    }

    final myId = _userId;
    if (myId == null) return;

    final preview = (message.content ?? '').trim();
    final previewText = preview.isEmpty
        ? null
        : (preview.length > 80 ? '${preview.substring(0, 80)}…' : preview);

    ChatProductContext? productUpdate;
    final tags = message.tags ?? const [];
    for (final tag in tags) {
      if (tag['tagType'] == 'product') {
        productUpdate = ChatProductContext.fromTagMap(
          Map<String, dynamic>.from(tag),
        );
        break;
      }
    }

    final idx = _cachedThreads.indexWhere((t) => t.id == message.chatId);
    if (idx < 0) {
      refreshThreads();
      return;
    }

    final old = _cachedThreads[idx];
    final bumpUnread =
        !message.isMine(myId) && message.chatId != _activeChatId;
    final updated = old.copyWith(
      lastMessagePreview: previewText ??
          (productUpdate != null
              ? 'Enquiry about ${productUpdate.name}'
              : old.lastMessagePreview),
      lastProductTag: productUpdate ?? old.lastProductTag,
      updatedAt: message.createdAt,
      lastMessageAt: message.createdAt,
      unreadCount: bumpUnread ? old.unreadCount + 1 : old.unreadCount,
    );

    _cachedThreads.removeAt(idx);
    _cachedThreads.insert(0, updated);
    _emitCachedThreads();
  }

  static void clearThreadUnread(String chatId) {
    final idx = _cachedThreads.indexWhere((t) => t.id == chatId);
    if (idx < 0) return;
    _cachedThreads[idx] = _cachedThreads[idx].copyWith(unreadCount: 0);
    _emitCachedThreads();
  }

  static void _emitCachedThreads() {
    if (!_threadsLiveController.isClosed) {
      _threadsLiveController.add(List<BackendChatThread>.from(_cachedThreads));
    }
  }

  static Future<void> _reloadThreadCache() async {
    _cachedThreads = await getThreads();
    _threadsWatchReady = true;
    _emitCachedThreads();
  }

  static void _ensureThreadsFallbackPoll() {
    if (_threadsFallbackPollTimer != null || _wsConnected) return;
    _threadsFallbackPollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_wsConnected) return;
      unawaited(_reloadThreadCache());
    });
  }

  static Future<void> _ensureThreadsWatchInitialized() async {
    if (_threadsWatchReady) return;

    await _reloadThreadCache();

    _threadsRefresh.listen((_) {
      unawaited(_reloadThreadCache());
    });

    _ensureThreadsFallbackPoll();
  }

  /// Notify all listeners to refresh threads (called after sending a message)
  static void refreshThreads() {
    _threadsRefreshController.add(null);
  }

  static const _messagingFirebaseUidKey = 'messaging_firebase_uid';

  /// Socket.IO namespace URL for real-time messaging.
  static String get messagingWsUrl {
    final root = ApiConfig.prod.replaceAll(RegExp(r'/+$'), '');
    return '$root/messaging';
  }

  /// Current Firebase ID token (call [ensureAuth] first).
  static Future<String> getAuthToken() async {
    await ensureAuth();
    return _authToken!;
  }

  static Future<void> ensureAuth({bool forceRefresh = false}) async {
    await ApiConfig.init();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated with Firebase');
    }

    final sp = await SharedPreferences.getInstance();
    final storedUid = sp.getString(_messagingFirebaseUidKey);
    if (storedUid != null && storedUid != user.uid) {
      await sp.remove('userId');
      await sp.remove('user_id');
      _userId = null;
      _authToken = null;
      _tokenFetchedAt = null;
    }

    final cacheValid = !forceRefresh &&
        _authToken != null &&
        _authToken!.isNotEmpty &&
        _userId != null &&
        _cachedFirebaseUid == user.uid &&
        _tokenFetchedAt != null &&
        DateTime.now().difference(_tokenFetchedAt!) < _tokenTtl;

    if (cacheValid) return;

    _authToken = await user.getIdToken(forceRefresh);
    if (_authToken == null || _authToken!.isEmpty) {
      throw Exception('Failed to get Firebase ID token');
    }

    await sp.setString(_messagingFirebaseUidKey, user.uid);
    _cachedFirebaseUid = user.uid;
    _tokenFetchedAt = DateTime.now();

    final cachedUserId = sp.getInt('userId') ?? sp.getInt('user_id');
    if (cachedUserId != null && cachedUserId > 0) {
      _userId = cachedUserId;
      return;
    }

    final userId = await _fetchNumericUserIdFromMe();
    if (userId == null) {
      throw Exception(
        'Could not resolve your account on the server. Please log in again.',
      );
    }

    await sp.setInt('userId', userId);
    await sp.setInt('user_id', userId);
    _userId = userId;
  }

  /// Clear in-memory auth cache (e.g. on sign-out).
  static void clearAuthCache() {
    _authToken = null;
    _userId = null;
    _cachedFirebaseUid = null;
    _tokenFetchedAt = null;
    _cachedThreads = [];
    _threadsWatchReady = false;
    _activeChatId = null;
    _wsConnected = false;
    _threadsFallbackPollTimer?.cancel();
    _threadsFallbackPollTimer = null;
  }

  /// Always load numeric DB user id for the current Firebase session.
  static Future<int?> _fetchNumericUserIdFromMe() async {
    if (_authToken == null || _authToken!.isEmpty) return null;
    try {
      final response = await http.get(
        ApiConfig.endpoint('/users/me'),
        headers: {'Authorization': _authHeader},
      ).timeout(_lookupTimeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;
      final data = json['data'] is Map<String, dynamic>
          ? json['data'] as Map<String, dynamic>
          : json;
      final rawId = data['id'] ?? data['userId'];
      if (rawId == null) return null;
      return rawId is int ? rawId : int.tryParse(rawId.toString());
    } catch (e) {
      print('[BackendChatService] Failed to fetch /users/me: $e');
      return null;
    }
  }

  static const Duration _lookupTimeout = Duration(seconds: 5);

  /// Resolve a marketplace / listing seller to a numeric backend user id.
  static Future<int?> resolvePeerUserId({
    int? ownerId,
    String? sellerUserId,
    String? serviceProviderId,
    String? merchantId,
  }) async {
    await ensureAuth();

    if (ownerId != null && ownerId > 0) return ownerId;

    final candidates = [sellerUserId, serviceProviderId, merchantId];
    for (final candidate in candidates) {
      if (candidate == null || candidate.trim().isEmpty) continue;
      final numeric = int.tryParse(candidate.trim());
      if (numeric != null && numeric > 0) return numeric;
    }

    for (final candidate in candidates) {
      if (candidate == null || candidate.trim().isEmpty) continue;
      final trimmed = candidate.trim();
      if (!_looksLikeFirebaseUid(trimmed)) continue;
      final uid = await getUserIdByFirebaseUid(trimmed);
      if (uid != null && uid > 0) return uid;
    }

    return null;
  }

  /// Resolve marketplace listing seller → numeric backend user id.
  static Future<int?> resolveMarketplaceSeller({
    int? sqlItemId,
    int? ownerId,
    String? sellerUserId,
    String? serviceProviderId,
    String? merchantId,
  }) async {
    await ensureAuth();

    if (ownerId != null && ownerId > 0) return ownerId;

    for (final raw in [sellerUserId, merchantId, serviceProviderId]) {
      if (raw == null || raw.trim().isEmpty) continue;
      final numeric = int.tryParse(raw.trim());
      if (numeric != null && numeric > 0) return numeric;
    }

    final lookups = <Future<int?>>[];

    if (sqlItemId != null && sqlItemId > 0) {
      lookups.add(_ownerIdFromMarketplaceItem(sqlItemId, quiet: true));
    }

    if (serviceProviderId != null && serviceProviderId.trim().isNotEmpty) {
      lookups.add(_userIdFromServiceProvider(serviceProviderId.trim(), quiet: true));
    }

    for (final raw in [sellerUserId, merchantId]) {
      if (raw == null || raw.trim().isEmpty) continue;
      final trimmed = raw.trim();
      if (_looksLikeFirebaseUid(trimmed)) {
        lookups.add(getUserIdByFirebaseUid(trimmed, quiet: true));
      }
    }

    if (lookups.isEmpty) return null;

    return _firstSuccessfulId(lookups);
  }

  /// Returns the first positive id from [futures], without waiting for slower ones.
  static Future<int?> _firstSuccessfulId(List<Future<int?>> futures) {
    if (futures.isEmpty) return Future.value(null);
    final completer = Completer<int?>();
    var remaining = futures.length;
    for (final future in futures) {
      future
          .then((id) {
            if (!completer.isCompleted && id != null && id > 0) {
              completer.complete(id);
            }
          })
          .catchError((_) {})
          .whenComplete(() {
            remaining--;
            if (remaining == 0 && !completer.isCompleted) {
              completer.complete(null);
            }
          });
    }
    return completer.future;
  }

  /// Resolve seller and create/open a direct chat (bounded time).
  static Future<BackendChatThread> startMerchantChat({
    int? sqlItemId,
    int? ownerId,
    String? sellerUserId,
    String? serviceProviderId,
    String? merchantId,
    required int myUserId,
  }) async {
    final sellerId = await resolveMarketplaceSeller(
      sqlItemId: sqlItemId,
      ownerId: ownerId,
      sellerUserId: sellerUserId,
      serviceProviderId: serviceProviderId,
      merchantId: merchantId,
    ).timeout(
      const Duration(seconds: 12),
      onTimeout: () => null,
    );

    if (sellerId == null || sellerId <= 0) {
      throw Exception(
        'Seller chat unavailable — could not link this listing to a seller account.',
      );
    }
    if (sellerId == myUserId) {
      throw Exception('This is your own listing');
    }

    return ensureChat(peerUserId: sellerId).timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw Exception(
        'Chat server is not responding. Check your connection and try again.',
      ),
    );
  }

  static bool _looksLikeFirebaseUid(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(value);
  }

  static int? _parseNumericId(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw > 0 ? raw : null;
    return int.tryParse(raw.toString());
  }

  static Future<int?> _ownerIdFromMarketplaceItem(int itemId, {bool quiet = false}) async {
    try {
      final response = await http.get(
        ApiConfig.endpoint('/marketplace/$itemId'),
        headers: {'Authorization': _authHeader, 'Accept': 'application/json'},
      ).timeout(_lookupTimeout);

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map) return null;
      final data = json['data'] is Map ? json['data'] as Map : json;
      return _parseNumericId(data['ownerId']);
    } catch (e) {
      if (!quiet) {
        print('[BackendChatService] marketplace owner lookup failed: $e');
      }
      return null;
    }
  }

  static Future<int?> _userIdFromServiceProvider(
    String serviceProviderId, {
    bool quiet = false,
  }) async {
    try {
      final response = await http.get(
        ApiConfig.endpoint('/serviceprovider/search/$serviceProviderId'),
        headers: {'Authorization': _authHeader, 'Accept': 'application/json'},
      ).timeout(_lookupTimeout);

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map) return null;

      final data = json['data'] is Map ? json['data'] as Map : json;
      final user = data['user'];
      if (user is Map) {
        return _parseNumericId(user['id']);
      }
      return _parseNumericId(data['userID'] ?? data['userId']);
    } catch (e) {
      if (!quiet) {
        print('[BackendChatService] service provider lookup failed: $e');
      }
      return null;
    }
  }

  static Future<int> getUserId() async {
    await ensureAuth();
    return _userId!;
  }

  /// Get numeric user ID by Firebase UID (for looking up seller/merchant IDs)
  static Future<int?> getUserIdByFirebaseUid(
    String firebaseUid, {
    bool quiet = false,
  }) async {
    if (firebaseUid.isEmpty) return null;
    await ensureAuth();

    try {
      // Try to get the user by their Firebase UID
      final url = ApiConfig.endpoint('/users').replace(
        queryParameters: {'firebaseUid': firebaseUid},
      );
      final response = await http.get(
        url,
        headers: {'Authorization': _authHeader},
      ).timeout(_lookupTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final users = json['data'] as List?;
        if (users != null && users.isNotEmpty) {
          final user = users.first as Map<String, dynamic>;
          final id = user['id'];
          if (id != null) {
            return id is int ? id : int.tryParse(id.toString());
          }
        }
      }
    } catch (e) {
      if (!quiet) {
        print('[BackendChatService] Error fetching user by Firebase UID: $e');
      }
    }
    return null;
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
      ).timeout(_lookupTimeout);

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

  /// Live thread list: initial REST load, WebSocket patches, manual refresh.
  static Stream<List<BackendChatThread>> watchThreads() async* {
    await _ensureThreadsWatchInitialized();
    yield List<BackendChatThread>.from(_cachedThreads);
    yield* _threadsLiveController.stream;
  }

  /// @deprecated Use [watchThreads] — kept for older call sites.
  static Stream<List<BackendChatThread>> threadsStream({
    Duration pollInterval = const Duration(seconds: 60),
  }) =>
      watchThreads();

  /// Get a specific chat
  static Future<BackendChatThread> getChat(String chatId) async {
    await ensureAuth();

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/chats/$chatId'),
        headers: {'Authorization': _authHeader},
      ).timeout(_lookupTimeout);

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
      ).timeout(_lookupTimeout);

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
    List<Map<String, dynamic>>? tags,
    Map<String, dynamic>? metadata,
    String? clientMessageId,
  }) async {
    await ensureAuth();

    try {
      final payload = <String, dynamic>{
        'content': content,
        'type': type,
      };
      if (tags != null && tags.isNotEmpty) payload['tags'] = tags;
      if (metadata != null && metadata.isNotEmpty) payload['metadata'] = metadata;
      if (clientMessageId != null && clientMessageId.isNotEmpty) {
        payload['clientMessageId'] = clientMessageId;
      }

      final response = await http
          .post(
            Uri.parse('$_baseUrl/chats/$chatId/messages'),
            headers: {
              'Authorization': _authHeader,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        final msg = BackendChatMessage.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
        // Notify all listeners to refresh threads list
        refreshThreads();
        return msg;
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
      final response = await http
          .put(
            Uri.parse('$_baseUrl/chats/$chatId/messages/$messageId'),
            headers: {
              'Authorization': _authHeader,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'content': newContent}),
          )
          .timeout(const Duration(seconds: 10));

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
      ).timeout(_lookupTimeout);

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

    if (peerUserId == _userId) {
      throw Exception('Cannot create a chat with yourself');
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/chats'),
            headers: {
              'Authorization': _authHeader,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'type': 'direct',
              // Backend pairs authenticated user with this peer id
              'participantIds': [peerUserId],
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201 || response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final chatData = body is Map ? body : body['data'] ?? body;
        return BackendChatThread.fromJson(chatData as Map<String, dynamic>);
      } else {
        print('[BackendChatService] Create chat error: ${response.statusCode}');
        print('[BackendChatService] Response body: ${response.body}');
        throw Exception('Failed to create chat: ${response.statusCode} - ${response.body}');
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
      await http
          .patch(
            Uri.parse('$_baseUrl/chats/$chatId/messages/bulk/read'),
            headers: {
              'Authorization': _authHeader,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'messageIds': messageIds}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      print('[BackendChatService] Error marking as read: $e');
      rethrow;
    }
  }

  /// Send test message to all users (TEST ONLY)
  static Future<int> sendTestMessageToAllUsers({
    required String testMessage,
  }) async {
    await ensureAuth();
    final myId = _userId!;

    try {
      // Fetch all users from /vero/users (users controller is at root, not /api/v1)
      final usersUrl = ApiConfig.endpoint('/users');
      final usersResponse = await http.get(
        usersUrl,
        headers: {'Authorization': _authHeader},
      ).timeout(_lookupTimeout);

      if (usersResponse.statusCode != 200) {
        throw Exception('Failed to fetch users: ${usersResponse.statusCode}');
      }

      final usersJson = jsonDecode(usersResponse.body);
      final users = usersJson['data'] as List? ?? [];
      int successCount = 0;

      for (final userJson in users) {
        final userId = userJson['id'] as int?;
        if (userId == null || userId == myId) continue;

        try {
          // Create or get chat with user
          final chat = await ensureChat(peerUserId: userId);

          // Send message
          await sendMessage(
            chatId: chat.id,
            content: testMessage,
            type: 'text',
          );

          successCount++;
          print('[BackendChatService] Sent test message to user $userId');
        } catch (e) {
          print('[BackendChatService] Failed to send to user $userId: $e');
          // Continue with next user on failure
        }
      }

      print(
          '[BackendChatService] Test messages sent to $successCount users');
      return successCount;
    } catch (e) {
      print('[BackendChatService] Error sending test messages: $e');
      rethrow;
    }
  }
}

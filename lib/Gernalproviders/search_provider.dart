import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vero360_app/GeneralModels/messaging_models.dart';
import 'package:vero360_app/GernalServices/search_service.dart';

// Search service provider
final searchServiceProvider = Provider((ref) {
  return SearchService();
});

// Current search query
final searchQueryProvider = StateProvider<String>((ref) => '');

// Search results (messages)
final messageSearchResultsProvider =
    FutureProvider.family<List<Message>, String>((ref, keyword) async {
  if (keyword.isEmpty) return [];
  
  final service = ref.watch(searchServiceProvider);
  return service.searchMessages(keyword: keyword);
});

// Search results (chats)
final chatSearchResultsProvider =
    FutureProvider.family<List<Chat>, String>((ref, keyword) async {
  if (keyword.isEmpty) return [];
  
  final service = ref.watch(searchServiceProvider);
  // Placeholder userId - should come from auth context
  return service.searchChats(keyword: keyword, userId: 'current_user_id');
});

// Recent searches
final recentSearchesProvider =
    FutureProvider<List<String>>((ref) async {
  final service = ref.watch(searchServiceProvider);
  // Placeholder userId - should come from auth context
  return service.getRecentSearches('current_user_id');
});

// Messages by sender
final messagesBySenderProvider =
    FutureProvider.family<List<Message>, String>((ref, senderId) async {
  final service = ref.watch(searchServiceProvider);
  return service.searchMessagesBySender(senderId: senderId);
});

// Messages by date range
final messagesByDateRangeProvider = FutureProvider.family<
    List<Message>,
    ({DateTime startDate, DateTime endDate})>((ref, params) async {
  final service = ref.watch(searchServiceProvider);
  return service.searchMessagesByDateRange(
    startDate: params.startDate,
    endDate: params.endDate,
  );
});

// Messages with attachments
final messagesWithAttachmentsProvider =
    FutureProvider.family<List<Message>, String>((ref, chatId) async {
  final service = ref.watch(searchServiceProvider);
  return service.searchMessagesWithAttachments(chatId: chatId);
});

/// Notifier for managing search state
class SearchNotifier extends StateNotifier<SearchState> {
  final Ref ref;

  SearchNotifier(this.ref)
      : super(const SearchState(
          query: '',
          messageResults: <Message>[],
          chatResults: <Chat>[],
          recentSearches: <String>[],
          isSearching: false,
        ));

  void setQuery(String query) {
    state = state.copyWith(query: query);
  }

  void clearQuery() {
    state = const SearchState(
      query: '',
      messageResults: <Message>[],
      chatResults: <Chat>[],
      recentSearches: <String>[],
      isSearching: false,
    );
  }

  Future<void> search(String keyword) async {
    if (keyword.isEmpty) {
      state = state.copyWith(
        messageResults: <Message>[],
        chatResults: <Chat>[],
      );
      return;
    }

    state = state.copyWith(isSearching: true);

    try {
      final service = ref.read(searchServiceProvider);
      
      final messageResults = await service.searchMessages(keyword: keyword);
      final chatResults = await service.searchChats(
        keyword: keyword,
        userId: 'current_user_id', // Should come from auth context
      );

      // Save search
      await service.saveSearch('current_user_id', keyword);

      state = state.copyWith(
        messageResults: messageResults,
        chatResults: chatResults,
        isSearching: false,
      );
    } catch (e) {
      developer.log('[SearchNotifier] Search error: $e');
      state = state.copyWith(isSearching: false);
    }
  }

  Future<void> clearRecentSearches() async {
    try {
      final service = ref.read(searchServiceProvider);
      await service.clearRecentSearches('current_user_id');
      state = state.copyWith(recentSearches: <String>[]);
    } catch (e) {
      developer.log('[SearchNotifier] Error clearing recent searches: $e');
    }
  }
}

/// State model for search
class SearchState {
  final String query;
  final List<Message> messageResults;
  final List<Chat> chatResults;
  final List<String> recentSearches;
  final bool isSearching;

  const SearchState({
    required this.query,
    required this.messageResults,
    required this.chatResults,
    required this.recentSearches,
    required this.isSearching,
  });

  SearchState copyWith({
    String? query,
    List<Message>? messageResults,
    List<Chat>? chatResults,
    List<String>? recentSearches,
    bool? isSearching,
  }) {
    return SearchState(
      query: query ?? this.query,
      messageResults: messageResults ?? this.messageResults,
      chatResults: chatResults ?? this.chatResults,
      recentSearches: recentSearches ?? this.recentSearches,
      isSearching: isSearching ?? this.isSearching,
    );
  }
}

/// Provider for the search notifier
final searchNotifierProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref);
});

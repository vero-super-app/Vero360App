import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/models/messaging_models.dart';
import 'package:vero360_app/providers/search_provider.dart';

/// Screen for searching messages and chats
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late TextEditingController _searchController;
  String _selectedFilter = 'all'; // 'all', 'messages', 'chats'

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    ref.read(searchNotifierProvider.notifier).search(query);
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(searchNotifierProvider.notifier).clearQuery();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchNotifierProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search messages & chats...',
            border: InputBorder.none,
            hintStyle: theme.inputDecorationTheme.hintStyle,
          ),
          onChanged: (value) {
            ref.read(searchNotifierProvider.notifier).setQuery(value);
            _performSearch(value);
          },
          textInputAction: TextInputAction.search,
          onSubmitted: _performSearch,
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSearch,
            ),
        ],
      ),
      body: _searchController.text.isEmpty
          ? _buildEmptyState(context, searchState)
          : _buildSearchResults(context, searchState),
    );
  }

  Widget _buildEmptyState(BuildContext context, SearchState searchState) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Recent searches
        if (searchState.recentSearches.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Searches',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {
                  ref
                      .read(searchNotifierProvider.notifier)
                      .clearRecentSearches();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: searchState.recentSearches
                .map((search) => GestureDetector(
                      onTap: () {
                        _searchController.text = search;
                        _performSearch(search);
                      },
                      child: Chip(
                        label: Text(search),
                        onDeleted: () {
                          // Remove individual search
                        },
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 32),
        ],

        // Search suggestions
        Text(
          'Tips',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.search),
          title: const Text('Search messages by keyword'),
          subtitle: const Text('Find messages containing specific text'),
          onTap: () {
            _searchController.text = '';
            _searchController.clear();
          },
        ),
        ListTile(
          leading: const Icon(Icons.chat),
          title: const Text('Search chats by name'),
          subtitle: const Text('Find conversations by chat name'),
          onTap: () {
            _searchController.text = '';
            _searchController.clear();
          },
        ),
      ],
    );
  }

  Widget _buildSearchResults(BuildContext context, SearchState searchState) {
    final theme = Theme.of(context);

    if (searchState.isSearching) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final totalResults =
        searchState.messageResults.length + searchState.chatResults.length;

    if (totalResults == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try different keywords',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(
                text: 'All (${totalResults})',
              ),
              Tab(
                text: 'Messages (${searchState.messageResults.length})',
              ),
              Tab(
                text: 'Chats (${searchState.chatResults.length})',
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildAllResults(context, searchState),
                _buildMessageResults(context, searchState),
                _buildChatResults(context, searchState),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllResults(BuildContext context, SearchState searchState) {
    return ListView(
      children: [
        if (searchState.chatResults.isNotEmpty) ...[
          _buildSectionHeader(context, 'Chats'),
          ...searchState.chatResults
              .take(3)
              .map((chat) => _buildChatTile(context, chat)),
          if (searchState.chatResults.length > 3)
            _buildViewMoreButton(context, 'View all chats'),
        ],
        if (searchState.messageResults.isNotEmpty) ...[
          if (searchState.chatResults.isNotEmpty)
            const Divider(height: 32),
          _buildSectionHeader(context, 'Messages'),
          ...searchState.messageResults
              .take(5)
              .map((msg) => _buildMessageTile(context, msg)),
          if (searchState.messageResults.length > 5)
            _buildViewMoreButton(context, 'View all messages'),
        ],
      ],
    );
  }

  Widget _buildMessageResults(BuildContext context, SearchState searchState) {
    if (searchState.messageResults.isEmpty) {
      return Center(
        child: Text(
          'No messages found',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      itemCount: searchState.messageResults.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final message = searchState.messageResults[index];
        return _buildMessageTile(context, message);
      },
    );
  }

  Widget _buildChatResults(BuildContext context, SearchState searchState) {
    if (searchState.chatResults.isEmpty) {
      return Center(
        child: Text(
          'No chats found',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      itemCount: searchState.chatResults.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final chat = searchState.chatResults[index];
        return _buildChatTile(context, chat);
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildViewMoreButton(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextButton(
        onPressed: () {
          // Navigate to full results
        },
        child: Text(label),
      ),
    );
  }

  Widget _buildMessageTile(BuildContext context, Message message) {
    final theme = Theme.of(context);
    final query = _searchController.text.toLowerCase();
    final content = message.content;
    final startIndex = content.toLowerCase().indexOf(query);
    final preview = startIndex >= 0
        ? '...${content.substring(
              (startIndex - 20).clamp(0, startIndex),
              (startIndex + query.length + 20).clamp(
                startIndex + query.length,
                content.length,
              ),
            )}...'
        : content.substring(0, (100).clamp(0, content.length));

    return ListTile(
      leading: CircleAvatar(
        child: Text(message.senderName?.substring(0, 1) ?? 'U'),
      ),
      title: Text(message.senderName ?? 'Unknown'),
      subtitle: Text(
        preview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        _formatTime(message.createdAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.grey,
        ),
      ),
      onTap: () {
        // Navigate to message in chat
        Navigator.pop(context);
      },
    );
  }

  Widget _buildChatTile(BuildContext context, Chat chat) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        child: Text(
          chat.name?.substring(0, 1) ?? 'C',
        ),
      ),
      title: Text(chat.name ?? 'Unnamed Chat'),
      subtitle: Text(
        chat.description ?? 'No description',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        '${chat.participantCount ?? 0} members',
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.grey,
        ),
      ),
      onTap: () {
        // Navigate to chat
        Navigator.pop(context);
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';

    return '${time.month}/${time.day}';
  }
}

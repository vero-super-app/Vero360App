import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/models/call_model.dart';
import 'package:vero360_app/providers/call_provider.dart';
import 'package:vero360_app/widgets/call_widget.dart';
import 'package:vero360_app/widgets/messaging_colors.dart';

class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen> {
  String _filterType = 'all'; // all, incoming, outgoing, missed

  @override
  Widget build(BuildContext context) {
    final callHistory = ref.watch(callHistoryProvider);

    // Filter based on selection
    final filteredHistory = _filterCalls(callHistory);

    return Scaffold(
      backgroundColor: MessagingColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: MessagingColors.background,
        foregroundColor: MessagingColors.title,
        title: const Text('Call History'),
        actions: [
          // Clear history button
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _showClearDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _filterType == 'all',
                    onTap: () => setState(() => _filterType = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Incoming',
                    selected: _filterType == 'incoming',
                    onTap: () => setState(() => _filterType = 'incoming'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Outgoing',
                    selected: _filterType == 'outgoing',
                    onTap: () => setState(() => _filterType = 'outgoing'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Missed',
                    selected: _filterType == 'missed',
                    onTap: () => setState(() => _filterType = 'missed'),
                  ),
                ],
              ),
            ),
          ),

          // Call list
          Expanded(
            child: filteredHistory.isEmpty
                ? _EmptyState(filterType: _filterType)
                : ListView.builder(
                    itemCount: filteredHistory.length,
                    itemBuilder: (context, index) {
                      final entry = filteredHistory[index];
                      return CallHistoryItemWidget(
                        entry: entry,
                        onTap: () {
                          // Could show call details or initiate new call
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Call with ${entry.peerName}'),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<CallHistoryEntry> _filterCalls(List<CallHistoryEntry> calls) {
    switch (_filterType) {
      case 'incoming':
        return calls.where((c) => c.isIncoming).toList();
      case 'outgoing':
        return calls.where((c) => !c.isIncoming).toList();
      case 'missed':
        return calls.where((c) => c.status == CallStatus.missed).toList();
      case 'all':
      default:
        return calls;
    }
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Call History'),
        content: const Text(
          'Are you sure you want to clear all call history? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              // Clear history
              ref.read(callHistoryProvider.notifier).state = [];
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Call history cleared')),
              );
            },
            child: const Text('Clear',
                style: TextStyle(color: MessagingColors.error)),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: MessagingColors.chip,
      selectedColor: MessagingColors.brandOrangeSoft,
      labelStyle: TextStyle(
        color: selected ? MessagingColors.brandOrange : MessagingColors.body,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String filterType;

  const _EmptyState({required this.filterType});

  String get _message {
    switch (filterType) {
      case 'incoming':
        return 'No incoming calls';
      case 'outgoing':
        return 'No outgoing calls';
      case 'missed':
        return 'No missed calls';
      case 'all':
      default:
        return 'No calls yet';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.call_end,
            size: 64,
            color: MessagingColors.brandOrangePale,
          ),
          const SizedBox(height: 16),
          Text(
            _message,
            style: const TextStyle(
              fontSize: 16,
              color: MessagingColors.subtitle,
            ),
          ),
        ],
      ),
    );
  }
}

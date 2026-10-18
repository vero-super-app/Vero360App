import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vero360_app/features/Reels/reel_feed_view.dart';
import 'package:vero360_app/features/Reels/reel_model.dart';
import 'package:vero360_app/features/Reels/reel_service.dart';
import 'package:vero360_app/features/Reels/user_reels_page.dart';

const _kOrange = Color(0xFFFF8A00);

/// Find a shop (or anyone) who posts reels and open their reels.
class ReelSearchPage extends StatefulWidget {
  const ReelSearchPage({super.key});

  @override
  State<ReelSearchPage> createState() => _ReelSearchPageState();
}

class _ReelSearchPageState extends State<ReelSearchPage> {
  final _service = ReelService.instance;
  final _query = TextEditingController();
  Timer? _debounce;
  List<ReelCreator>? _results;
  bool _shopsOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _search);
    setState(() {});
  }

  Future<void> _search() async {
    try {
      final results = await _service.searchCreators(_query.text);
      if (!mounted) return;
      setState(() {
        _results = results;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not search right now');
    }
  }

  void _open(ReelCreator c) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => UserReelsPage(
        ownerId: c.id,
        ownerName: c.name,
        ownerPhoto: c.photo,
        isMerchant: c.isMerchant,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final all = _results;
    final results =
        all == null ? null : (_shopsOnly ? all.where((c) => c.isMerchant).toList() : all);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _query,
            autofocus: true,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search shops and creators',
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.black45),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.black45),
                      onPressed: () {
                        _query.clear();
                        _onChanged('');
                      },
                    ),
              filled: true,
              fillColor: const Color(0xFFF2F3F5),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: !_shopsOnly,
                  onTap: () => setState(() => _shopsOnly = false),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Shops',
                  icon: Icons.storefront_rounded,
                  selected: _shopsOnly,
                  onTap: () => setState(() => _shopsOnly = true),
                ),
              ],
            ),
          ),
          Expanded(child: _body(results)),
        ],
      ),
    );
  }

  Widget _body(List<ReelCreator>? results) {
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.black54)));
    }
    if (results == null) {
      return const Center(child: CircularProgressIndicator(color: _kOrange));
    }
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, size: 48, color: Colors.black26),
              const SizedBox(height: 12),
              Text(
                _query.text.trim().isEmpty
                    ? 'No one has posted reels yet.'
                    : 'No shops or creators match "${_query.text.trim()}".',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
      itemBuilder: (context, i) {
        final c = results[i];
        return ListTile(
          onTap: () => _open(c),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: ReelAvatar(url: c.photo, name: c.name, size: 46),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  c.name.isEmpty ? 'Vero360 user' : c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (c.isMerchant) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified_rounded, size: 16, color: _kOrange),
              ],
            ],
          ),
          subtitle: Text(
            '${c.isMerchant ? 'Shop · ' : ''}'
            '${c.reelCount} reel${c.reelCount == 1 ? '' : 's'} · '
            '${reelCompact(c.viewCount)} views',
            style: const TextStyle(color: Colors.black54, fontSize: 12.5),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black38),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : Colors.black87;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.black : const Color(0xFFF2F3F5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

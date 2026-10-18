import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vero360_app/features/Reels/reel_model.dart';
import 'package:vero360_app/features/Reels/reel_service.dart';

const kSpotifyGreen = Color(0xFF1DB954);
const _kInk = Color(0xFF1B1D22);

/// Bottom sheet to search Spotify and pick one song for a reel.
Future<ReelMusic?> showSpotifyPicker(BuildContext context) {
  return showModalBottomSheet<ReelMusic>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _SpotifyPickerSheet(),
  );
}

class _SpotifyPickerSheet extends StatefulWidget {
  const _SpotifyPickerSheet();

  @override
  State<_SpotifyPickerSheet> createState() => _SpotifyPickerSheetState();
}

class _SpotifyPickerSheetState extends State<_SpotifyPickerSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<ReelMusic> _results = const [];
  bool _loading = false;
  String? _error;
  int _searchId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    setState(() {});
    if (text.trim().isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final id = ++_searchId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ReelService.instance.searchSpotify(_query.text);
      if (!mounted || id != _searchId) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _searchId) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Add music',
                        style: TextStyle(
                            color: _kInk, fontSize: 19, fontWeight: FontWeight.w900)),
                  ),
                  const _PoweredBySpotify(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Search songs or artists',
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
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_loading)
              const LinearProgressIndicator(
                minHeight: 2,
                color: kSpotifyGreen,
                backgroundColor: Colors.transparent,
              )
            else
              const SizedBox(height: 2),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return _Message(icon: Icons.cloud_off_rounded, text: _error!);
    }
    if (_query.text.trim().isEmpty) {
      return const _Message(
        icon: Icons.music_note_rounded,
        text: 'Search for a song to tag on your reel.\n'
            'Viewers can tap it to listen on Spotify.',
      );
    }
    if (_results.isEmpty) {
      return _loading
          ? const SizedBox.shrink()
          : const _Message(icon: Icons.search_off_rounded, text: 'No songs found.');
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final m = _results[i];
        return ListTile(
          onTap: () => Navigator.pop(context, m),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: m.image.startsWith('http')
                  ? Image.network(m.image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _ArtFallback())
                  : const _ArtFallback(),
            ),
          ),
          title: Text(m.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _kInk, fontWeight: FontWeight.w800)),
          subtitle: Text(m.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black54)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F3F5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text('Use',
                style: TextStyle(color: _kInk, fontWeight: FontWeight.w800)),
          ),
        );
      },
    );
  }
}

class _PoweredBySpotify extends StatelessWidget {
  const _PoweredBySpotify();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kSpotifyGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq_rounded, size: 14, color: kSpotifyGreen),
          SizedBox(width: 4),
          Text('Spotify',
              style: TextStyle(
                  color: kSpotifyGreen, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ArtFallback extends StatelessWidget {
  const _ArtFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFFE8F8EE),
        child: Icon(Icons.music_note_rounded, color: kSpotifyGreen),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.black26),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

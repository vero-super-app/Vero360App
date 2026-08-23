import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/GeneralModels/tender.models.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/GernalServices/tenders_service.dart';

class TendersPage extends StatefulWidget {
  const TendersPage({super.key});

  @override
  State<TendersPage> createState() => _TendersPageState();
}

class _TendersPageState extends State<TendersPage> {
  static const _brandOrange = Color(0xFFFF8A00);

  final _service = const TendersService();
  final _searchController = TextEditingController();

  List<TenderPost> _tenders = [];
  bool _loading = false;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadTenders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTenders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.fetchTenders();
      if (!mounted) return;
      setState(() => _tenders = items);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TenderPost> get _visible {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return _tenders;
    return _tenders.where((t) {
      return t.title.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q) ||
          (t.buyer ?? '').toLowerCase().contains(q) ||
          (t.reference ?? '').toLowerCase().contains(q) ||
          (t.location ?? '').toLowerCase().contains(q) ||
          t.sourceLabel.toLowerCase().contains(q);
    }).toList();
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return DateFormat('d MMM yyyy').format(d.toLocal());
  }

  Uri? _parseUri(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (!s.contains('://') && RegExp(r'^[\w.-]+\.[\w.-]+').hasMatch(s)) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  Future<void> _openUrl(String raw, {required String failMsg}) async {
    final uri = _parseUri(raw);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failMsg), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failMsg), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failMsg), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tenders'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search title, buyer, reference…',
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadTenders,
        child: _buildBody(visible),
      ),
    );
  }

  Widget _buildBody(List<TenderPost> visible) {
    if (_loading && _tenders.isEmpty && _error == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_error != null && _tenders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: _loadTenders,
              style: FilledButton.styleFrom(backgroundColor: _brandOrange),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    if (visible.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.description_outlined,
              size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isEmpty
                ? 'No open tenders yet.\nPull down to refresh.'
                : 'No tenders match your search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _buildCard(visible[i]),
    );
  }

  Widget _buildCard(TenderPost t) {
    final closed = t.isClosed;
    final soon = t.isClosingSoon;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    t.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _Chip(label: t.sourceLabel),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if ((t.buyer ?? '').isNotEmpty)
                  _Meta(icon: Icons.business_outlined, label: t.buyer!),
                if ((t.reference ?? '').isNotEmpty)
                  _Meta(icon: Icons.tag, label: t.reference!),
                if ((t.location ?? '').isNotEmpty)
                  _Meta(icon: Icons.place_outlined, label: t.location!),
                if (closed)
                  const _Chip(label: 'Closed', tone: _ChipTone.danger)
                else if (soon)
                  const _Chip(label: 'Closing soon', tone: _ChipTone.warn),
              ],
            ),
            if (t.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                t.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Published ${_formatDate(t.publishedAt)} · Closes ${_formatDate(t.closingAt)}',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.share, size: 20),
                  color: _brandOrange,
                  onPressed: () {
                    Share.share(
                      'Tender on Vero360:\n${t.title}\n${t.tenderUrl}',
                    );
                  },
                ),
                const Spacer(),
                if ((t.documentUrl ?? '').isNotEmpty)
                  TextButton(
                    onPressed: () => _openUrl(
                      t.documentUrl!,
                      failMsg: 'Could not open document.',
                    ),
                    child: const Text('Document'),
                  ),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: () => _openUrl(
                    t.tenderUrl,
                    failMsg: 'Could not open tender notice.',
                  ),
                  child: const Text('Open notice'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _ChipTone { normal, danger, warn }

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.tone = _ChipTone.normal});
  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    switch (tone) {
      case _ChipTone.danger:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFB91C1C);
        break;
      case _ChipTone.warn:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        break;
      case _ChipTone.normal:
        bg = const Color(0xFFFFF4E6);
        fg = const Color(0xFFD97706);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.black54),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}

// lib/Pages/Quickservices/jobs_page.dart

import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import 'package:vero360_app/GeneralModels/job.models.dart';
import 'package:vero360_app/GernalServices/jobs_service.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class JobsPage extends StatefulWidget {
  const JobsPage({super.key});

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage>
    with SingleTickerProviderStateMixin {
  static const _brandOrange = Color(0xFFFF8A00);

  final _service = const JobsService();
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Future<String>> _dlUrlCache = {};

  late final TabController _tabController;

  List<JobPost> _malawiJobs = [];
  List<JobPost> _internationalJobs = [];
  bool _loading = false;
  String? _error;
  String _searchQuery = '';

  bool _isHttp(String s) =>
      s.startsWith('http://') || s.startsWith('https://');

  bool _isGs(String s) => s.startsWith('gs://');

  bool _looksLikeBase64(String s) {
    final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
    if (x.length < 150) return false;
    return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
  }

  Future<String?> _toFirebaseDownloadUrl(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) return null;

    if (_isHttp(s)) return s;

    if (_dlUrlCache.containsKey(s)) return _dlUrlCache[s]!.then((v) => v);

    Future<String> fut() async {
      if (_isGs(s)) {
        return FirebaseStorage.instance.refFromURL(s).getDownloadURL();
      }
      return FirebaseStorage.instance.ref(s).getDownloadURL();
    }

    _dlUrlCache[s] = fut();
    try {
      return await _dlUrlCache[s]!;
    } catch (_) {
      return null;
    }
  }

  Widget _imageFromAnySource(
    String raw, {
    BoxFit fit = BoxFit.cover,
  }) {
    final s = raw.trim();

    if (s.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_rounded),
      );
    }

    if (_looksLikeBase64(s)) {
      try {
        final base64Part = s.contains(',') ? s.split(',').last : s;
        final bytes = base64Decode(base64Part);
        return Image.memory(bytes, fit: fit);
      } catch (_) {}
    }

    if (_isHttp(s)) {
      return Image.network(
        s,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported_rounded),
        ),
        loadingBuilder: (c, child, progress) {
          if (progress == null) return child;
          return Container(
            color: Colors.grey.shade100,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        },
      );
    }

    return FutureBuilder<String?>(
      future: _toFirebaseDownloadUrl(s),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return Container(
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.image_not_supported_rounded),
          );
        }
        return Image.network(
          url,
          fit: fit,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.image_not_supported_rounded),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (mounted) setState(() {});
    });
    _loadJobs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Match backend: GET /jobs?region=malawi|international
      final results = await Future.wait([
        _service.fetchJobs(activeOnly: true, region: JobRegion.malawi),
        _service.fetchJobs(activeOnly: true, region: JobRegion.international),
      ]);
      if (!mounted) return;
      setState(() {
        _malawiJobs = results[0];
        _internationalJobs = results[1];
      });
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

  /// Normalize apply URLs from Remotive/Jooble/manual posts.
  Uri? _parseApplyUri(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    // Strip accidental wrapping quotes from JSON/HTML.
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

  static const _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// e.g. 2026-August 04
  String _formatPostedDate(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-${_monthNames[local.month - 1]} $day';
  }

  Future<void> _openJobLink(JobPost job) async {
    final raw = job.applyLink;
    final uri = _parseApplyUri(raw);

    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No apply link available for this job.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      // Don't gate on canLaunchUrl — it often returns false on Android 11+
      // even when the browser can open https links.
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open apply link on this device.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open apply link on this device.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobs & Vacancies'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.trim();
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: 'Search jobs (title, company, location)...',
                      prefixIcon: Icon(Icons.search),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                tabs: [
                  Tab(
                    text:
                        'Malawi${_malawiJobs.isEmpty ? '' : ' (${_malawiJobs.length})'}',
                  ),
                  Tab(
                    text:
                        'International${_internationalJobs.isEmpty ? '' : ' (${_internationalJobs.length})'}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadJobs,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildJobList(JobRegion.malawi),
            _buildJobList(JobRegion.international),
          ],
        ),
      ),
    );
  }

  List<JobPost> _filterJobs(List<JobPost> jobs) {
    if (_searchQuery.isEmpty) return jobs;
    final q = _searchQuery.toLowerCase();
    return jobs.where((job) {
      return job.position.toLowerCase().contains(q) ||
          job.description.toLowerCase().contains(q) ||
          (job.company ?? '').toLowerCase().contains(q) ||
          (job.location ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Widget _buildJobList(JobRegion region) {
    final source =
        region == JobRegion.malawi ? _malawiJobs : _internationalJobs;
    final visibleJobs = _filterJobs(source);

    if (_loading && source.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && source.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: _loadJobs,
              style: FilledButton.styleFrom(
                backgroundColor: _brandOrange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    if (visibleJobs.isEmpty) {
      final label =
          region == JobRegion.malawi ? 'Malawi' : 'international';
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.work_outline, size: 56, color: Colors.black45),
          const SizedBox(height: 12),
          Text(
            source.isEmpty
                ? 'No $label job posts available at the moment.\nPlease check again later.'
                : 'No jobs match your search.\nTry a different keyword.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: visibleJobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) => _buildJobCard(visibleJobs[index]),
    );
  }

  Widget _buildJobCard(JobPost job) {
    final rawPhoto = (job.photoUrl ?? '').trim();
    final desc = job.description.trim();
    final String? imageSource =
        rawPhoto.isNotEmpty ? rawPhoto : (_isHttp(desc) ? desc : null);
    final applyUrl = job.applyLink;
    final hasApply = _parseApplyUri(applyUrl) != null;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageSource != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _imageFromAnySource(
                    imageSource,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (imageSource != null) const SizedBox(height: 8),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    job.position,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _RegionChip(region: job.region),
              ],
            ),
            if ((job.company ?? '').isNotEmpty ||
                (job.location ?? '').isNotEmpty ||
                job.isRemote) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if ((job.company ?? '').isNotEmpty)
                    _MetaChip(
                      icon: Icons.business_outlined,
                      label: job.company!,
                    ),
                  if ((job.location ?? '').isNotEmpty)
                    _MetaChip(
                      icon: Icons.place_outlined,
                      label: job.location!,
                    ),
                  if (job.isRemote)
                    const _MetaChip(
                      icon: Icons.wifi_tethering,
                      label: 'Remote',
                    ),
                ],
              ),
            ],
            const SizedBox(height: 6),

            Text(
              job.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                if (job.createdAt != null)
                  Text(
                    'Posted: ${_formatPostedDate(job.createdAt!)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                    ),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Share job',
                  icon: const Icon(Icons.share, size: 20),
                  color: _brandOrange,
                  onPressed: () {
                    if (!hasApply) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No apply link available to share.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                    final message =
                        'Hey, I saw this job on Vero – maybe you can try this opportunity:\n\n'
                        '${job.position}'
                        '${(job.company ?? '').isNotEmpty ? ' at ${job.company}' : ''}\n'
                        '$applyUrl';
                    Share.share(message);
                  },
                ),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        hasApply ? _brandOrange : Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: hasApply ? () => _openJobLink(job) : null,
                  child: Text(job.isExternal ? 'Apply' : 'Open link'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RegionChip extends StatelessWidget {
  const _RegionChip({required this.region});

  final JobRegion region;

  @override
  Widget build(BuildContext context) {
    final isMw = region == JobRegion.malawi;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isMw
            ? const Color(0xFFFF8A00).withValues(alpha: 0.12)
            : const Color(0xFF16284C).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isMw ? 'Malawi' : 'International',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: isMw ? const Color(0xFFFF8A00) : const Color(0xFF16284C),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

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
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ],
    );
  }
}

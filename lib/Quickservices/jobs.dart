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

class _JobsPageState extends State<JobsPage> {
  static const _brandOrange = Color(0xFFFF8A00);

  final _service = const JobsService();
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Future<String>> _dlUrlCache = {};

  List<JobPost> _jobs = [];
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

    // base64
    if (_looksLikeBase64(s)) {
      try {
        final base64Part = s.contains(',') ? s.split(',').last : s;
        final bytes = base64Decode(base64Part);
        return Image.memory(bytes, fit: fit);
      } catch (_) {}
    }

    // http(s)
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

    // firebase gs:// or storage path
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
    _loadJobs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _service.fetchJobs(activeOnly: true);
      setState(() => _jobs = data);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openJobLink(String url) async {
    if (url.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No job link available.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid job link.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!await canLaunchUrl(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open job link on this device.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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
                  hintText: 'Search jobs (title, description)...',
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
        onRefresh: _loadJobs,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // Filter jobs by search query (case-insensitive)
    final visibleJobs = _searchQuery.isEmpty
        ? _jobs
        : _jobs.where((job) {
            final q = _searchQuery.toLowerCase();
            return job.position.toLowerCase().contains(q) ||
                job.description.toLowerCase().contains(q);
          }).toList();

    if (_loading && _jobs.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _jobs.isEmpty) {
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
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.work_outline, size: 56, color: Colors.black45),
          const SizedBox(height: 12),
          Text(
            _jobs.isEmpty
                ? 'No job posts available at the moment.\nPlease check again later.'
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
      itemBuilder: (_, index) {
        final job = visibleJobs[index];
        final rawPhoto = (job.photoUrl ?? '').trim();
        final desc = job.description.trim();
        final String? imageSource = rawPhoto.isNotEmpty
            ? rawPhoto
            : (_isHttp(desc) ? desc : null);
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
                // Optional photo (supports http, gs://, storage paths, base64)
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
                if (imageSource != null)
                  const SizedBox(height: 8),

                Text(
                  job.position,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (job.createdAt != null)
                      Text(
                        'Posted: ${job.createdAt!.toLocal().toString().split(' ').first}',
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
                        final link = job.jobLink.trim();
                        if (link.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No job link available to share.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        final message =
                            'Hey, I saw this job on Vero – maybe you can try this opportunity:\n\n'
                            '${job.position}\n$link';
                        Share.share(message);
                      },
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandOrange,
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
                      onPressed: () => _openJobLink(job.jobLink),
                      child: const Text('Open job link'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

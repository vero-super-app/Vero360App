// lib/Pages/Quickservices/jobs_page.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/models/job.models.dart';
import 'package:vero360_app/services/jobs_service.dart';
import 'package:vero360_app/services/api_exception.dart';

class JobsPage extends StatefulWidget {
  const JobsPage({super.key});

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  static const _brandOrange = Color(0xFFFF8A00);
  static const _brandSoft = Color(0xFFFFE8CC);

  final _service = const JobsService();

  List<JobPost> _jobs = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadJobs();
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
      ),
      body: RefreshIndicator(
        onRefresh: _loadJobs,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
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

    if (_jobs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SizedBox(height: 60),
          Icon(Icons.work_outline, size: 56, color: Colors.black45),
          SizedBox(height: 12),
          Text(
            'No job posts available at the moment.\nPlease check again later.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final job = _jobs[index];
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
                // Optional photo
                if (job.photoUrl != null &&
                    job.photoUrl!.trim().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        job.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image,
                              color: Colors.black45),
                        ),
                      ),
                    ),
                  ),
                if (job.photoUrl != null &&
                    job.photoUrl!.trim().isNotEmpty)
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

// lib/pages/profile_from_link_page.dart
import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/user_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/GernalScreens/login_screen.dart';

class ProfileFromLinkPage extends StatefulWidget {
  const ProfileFromLinkPage({Key? key}) : super(key: key);

  @override
  State<ProfileFromLinkPage> createState() => _ProfileFromLinkPageState();
}

class _ProfileFromLinkPageState extends State<ProfileFromLinkPage> {
  final _svc = UserService();
  Map<String, dynamic>? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await _svc.getMe();
      if (!mounted) return;
      setState(() => _user = me);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Failed to load profile',
        isSuccess: false,
        errorMessage: e.toString(),
      );
      setState(() => _user = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFFFF8A00);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF222222),
        elevation: 0,
        title: const Text('My Profile'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_user == null
              ? _EmptyState(onLogin: _goLogin, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Top card
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 22,
                              spreadRadius: -8,
                              offset: Offset(0, 14),
                              color: Color(0x1A000000),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: brand.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.person_outline,
                                  size: 34, color: Color(0xFF6B778C)),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (_user?['name'] ??
                                            _user?['fullName'] ??
                                            'User')
                                        .toString(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF222222),
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (_user?['email'] ?? _user?['phone'] ?? '')
                                        .toString(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                            color: const Color(0xFF6B778C)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Details card
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 22,
                              spreadRadius: -8,
                              offset: Offset(0, 14),
                              color: Color(0x1A000000),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _kv(
                              icon: Icons.badge_outlined,
                              label: 'ID',
                              value: (_user?['id'] ??
                                      _user?['_id'] ??
                                      '')
                                  .toString(),
                            ),
                            const SizedBox(height: 10),
                            _kv(
                              icon: Icons.mail_outline,
                              label: 'Email',
                              value: (_user?['email'] ?? '').toString(),
                            ),
                            const SizedBox(height: 10),
                            _kv(
                              icon: Icons.phone_outlined,
                              label: 'Phone',
                              value: (_user?['phone'] ?? '').toString(),
                            ),
                            if (_user?['createdAt'] != null) ...[
                              const SizedBox(height: 10),
                              _kv(
                                icon: Icons.event_outlined,
                                label: 'Joined',
                                value: _user!['createdAt'].toString(),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.logout),
                              label: const Text('Log in as different user'),
                              onPressed: _goLogin,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: brand,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Looks good'),
                              onPressed: () {
                                Navigator.of(context).maybePop();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )),
    );
  }

  Widget _kv({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF6B778C)),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF6B778C)),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  void _goLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onLogin;
  const _EmptyState({Key? key, required this.onRetry, required this.onLogin})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFFFF8A00);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: brand.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.person_search_outlined,
                  size: 36, color: Color(0xFF6B778C)),
            ),
            const SizedBox(height: 12),
            const Text(
              'We couldn’t load your profile.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Try again, or log in to refresh your session.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: const Color(0xFF6B778C)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  onPressed: onRetry,
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Login'),
                  onPressed: onLogin,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

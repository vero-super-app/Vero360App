import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

Future<bool?> openKycSession(BuildContext context, String verificationUrl) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => _KycWebViewPage(verificationUrl: verificationUrl),
    ),
  );
}

class _KycWebViewPage extends StatefulWidget {
  final String verificationUrl;

  const _KycWebViewPage({required this.verificationUrl});

  @override
  State<_KycWebViewPage> createState() => _KycWebViewPageState();
}

class _KycWebViewPageState extends State<_KycWebViewPage> {
  static const _orange = Color(0xFFFF8A00);
  static const _ink = Color(0xFF141414);

  late final WebViewController _controller;
  bool _loading = true;
  bool _finished = false;
  double _progress = 0.08;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
    _prepareAndLoad();
  }

  WebViewController _buildController() {
    late final PlatformWebViewControllerCreationParams params;
    if (!kIsWeb && WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (WebViewPermissionRequest request) async {
        for (final type in request.types) {
          if (type == WebViewPermissionResourceType.camera) {
            await Permission.camera.request();
          } else if (type == WebViewPermissionResourceType.microphone) {
            await Permission.microphone.request();
          }
        }
        final camOk =
            !request.types.contains(WebViewPermissionResourceType.camera) ||
                await Permission.camera.isGranted;
        final micOk =
            !request.types.contains(WebViewPermissionResourceType.microphone) ||
                await Permission.microphone.isGranted;
        if (camOk && micOk) {
          await request.grant();
        } else {
          await request.deny();
        }
      },
    );

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _progress = (p / 100).clamp(0.08, 1.0));
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _progress = 0.08;
              });
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _loading = false;
                _progress = 1;
              });
            }
            _maybeComplete(url);
          },
          onNavigationRequest: (request) {
            _maybeComplete(request.url);
            return NavigationDecision.navigate;
          },
        ),
      );

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      platform.setMediaPlaybackRequiresUserGesture(false);
    }

    return controller;
  }

  Future<void> _prepareAndLoad() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await [
        Permission.camera,
        Permission.microphone,
      ].request();
    }
    if (!mounted) return;
    await _controller.loadRequest(Uri.parse(widget.verificationUrl));
  }

  void _maybeComplete(String url) {
    if (_finished) return;
    final u = url.toLowerCase();
    final done = u.contains('status=approved') ||
        u.contains('status=completed') ||
        u.contains('/success') ||
        u.contains('verification-complete') ||
        u.contains('decision=approved');
    if (!done) return;
    _finished = true;
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Identity check',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _ink,
              ),
            ),
            Text(
              'Powered by Didit',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: Color(0xFF6B6B6B),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: _orange),
            child: const Text(
              'Done',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: AnimatedOpacity(
            opacity: _loading ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 3,
              backgroundColor: const Color(0xFFFFF3E6),
              color: _orange,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const ColoredBox(
              color: Color(0xFFFFFBF7),
              child: Center(child: _WebLoadingCard()),
            ),
        ],
      ),
    );
  }
}

class _WebLoadingCard extends StatelessWidget {
  const _WebLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFF9A1F), Color(0xFFE86F00)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8A00).withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Opening secure session…',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Color(0xFF141414),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Keep this screen open',
          style: TextStyle(
            fontSize: 13,
            color: const Color(0xFF6B6B6B).withValues(alpha: 0.95),
          ),
        ),
      ],
    );
  }
}

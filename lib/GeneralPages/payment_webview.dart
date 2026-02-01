import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PaymentWebView extends StatefulWidget {
  final String checkoutUrl;

  /// If provided, we detect success/failure by matching URL startsWith.
  final String? successUrlPrefix;
  final String? failureUrlPrefix;

  const PaymentWebView({
    Key? key,
    required this.checkoutUrl,
    this.successUrlPrefix,
    this.failureUrlPrefix,
  }) : super(key: key);

  @override
  State<PaymentWebView> createState() => _PaymentWebViewState();
}

class _PaymentWebViewState extends State<PaymentWebView> {
  late final WebViewController _c;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (req) {
            final url = req.url;
            // Basic success/failure detection (tune to your real return URLs)
            if (widget.successUrlPrefix != null && url.startsWith(widget.successUrlPrefix!)) {
              Navigator.pop(context, true);
              return NavigationDecision.prevent;
            }
            if (widget.failureUrlPrefix != null && url.startsWith(widget.failureUrlPrefix!)) {
              Navigator.pop(context, false);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Payment')),
      body: Stack(
        children: [
          WebViewWidget(controller: _c),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

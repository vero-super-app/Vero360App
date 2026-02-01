import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PayChanguInlinePopup extends StatefulWidget {
  final String publicKey;
  final double amount;
  final String currency;
  final String callbackUrl; // server callback/notify URL
  final String returnUrl;   // where the user gets redirected after pay
  final String email;
  final String name;

  const PayChanguInlinePopup({
    Key? key,
    required this.publicKey,
    required this.amount,
    required this.currency,
    required this.callbackUrl,
    required this.returnUrl,
    required this.email,
    required this.name,
  }) : super(key: key);

  @override
  State<PayChanguInlinePopup> createState() => _PayChanguInlinePopupState();
}

class _PayChanguInlinePopupState extends State<PayChanguInlinePopup> {
  late final WebViewController _c;

  @override
  void initState() {
    super.initState();

    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final url = req.url;
            // If PayChangu redirects back to returnUrl with status, detect it:
            if (url.startsWith(widget.returnUrl)) {
              Navigator.pop(context, true); // success-ish; verify on server by callback
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.dataFromString(
        _html(),
        mimeType: 'text/html',
        encoding: Encoding.getByName('utf-8'),
      ));
  }

  String _html() {
    final txRef = DateTime.now().millisecondsSinceEpoch.toString();
    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script src="https://in.paychangu.com/js/popup.js"></script>
    <style>
      body, html { margin:0; padding:0; height:100%; display:flex; align-items:center; justify-content:center; background:#f5f5f5; font-family:system-ui,-apple-system,Roboto,Arial; }
      #box { width:92%; max-width:600px; background:#fff; padding:20px; border-radius:12px; box-shadow:0 8px 24px rgba(0,0,0,.08); text-align:center; }
      button { padding:12px 18px; background:#0a7; color:#fff; border:none; border-radius:8px; font-size:16px; cursor:pointer; }
      h2 { margin:0 0 10px; }
      p { color:#555; }
    </style>
  </head>
  <body>
    <div id="box">
      <h2>Card Payment</h2>
      <p>Amount: <b>${widget.currency} ${widget.amount.toStringAsFixed(2)}</b></p>
      <button onclick="makePayment()">Pay Now</button>
    </div>
    <script>
      function makePayment() {
        PaychanguCheckout({
          public_key: "${widget.publicKey}",
          tx_ref: "$txRef",
          amount: ${widget.amount},
          currency: "${widget.currency}",
          callback_url: "${widget.callbackUrl}",
          return_url: "${widget.returnUrl}",
          customer: {
            email: "${widget.email}",
            first_name: "${widget.name}"
          },
          customization: {
            title: "Marketplace Purchase",
            description: "Order payment"
          }
        });
      }
    </script>
  </body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pay with PayChangu')),
      body: WebViewWidget(controller: _c),
    );
  }
}

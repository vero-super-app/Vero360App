import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// WhatsApp-style tappable links inside chat bubbles.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(
    this.text, {
    super.key,
    required this.style,
    this.linkColor,
  });

  final String text;
  final TextStyle style;
  final Color? linkColor;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  static final _urlRe = RegExp(
    r'((https?:\/\/|www\.)[^\s<>"{}|\\^`\[\]]+)|'
    r'([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})',
    caseSensitive: false,
  );

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      for (final r in _recognizers) {
        r.dispose();
      }
      _recognizers.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = widget.style.copyWith(
      color: widget.linkColor ?? const Color(0xFF2563EB),
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor ?? const Color(0xFF2563EB),
      fontWeight: FontWeight.w600,
    );

    final matches = _urlRe.allMatches(widget.text).toList();
    if (matches.isEmpty) {
      return Text(widget.text, style: widget.style);
    }

    if (_recognizers.isNotEmpty &&
        _recognizers.length != matches.length) {
      for (final r in _recognizers) {
        r.dispose();
      }
      _recognizers.clear();
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    var linkIdx = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(
          TextSpan(
            text: widget.text.substring(cursor, m.start),
            style: widget.style,
          ),
        );
      }
      final raw = m.group(0)!;
      TapGestureRecognizer recognizer;
      if (linkIdx < _recognizers.length) {
        recognizer = _recognizers[linkIdx];
      } else {
        recognizer = TapGestureRecognizer();
        _recognizers.add(recognizer);
      }
      recognizer.onTap = () => _open(raw);
      linkIdx++;
      spans.add(
        TextSpan(
          text: raw,
          style: linkStyle,
          recognizer: recognizer,
        ),
      );
      cursor = m.end;
    }
    if (cursor < widget.text.length) {
      spans.add(
        TextSpan(
          text: widget.text.substring(cursor),
          style: widget.style,
        ),
      );
    }

    return Text.rich(TextSpan(children: spans));
  }

  Future<void> _open(String raw) async {
    var target = raw.trim();
    if (target.contains('@') &&
        !target.contains('://') &&
        !target.toLowerCase().startsWith('www.')) {
      target = 'mailto:$target';
    } else if (target.toLowerCase().startsWith('www.')) {
      target = 'https://$target';
    }
    target = target.replaceFirst(RegExp(r'[),.!?;:]+$'), '');
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

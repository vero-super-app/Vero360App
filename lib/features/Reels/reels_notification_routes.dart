import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/features/Reels/Live/live_hub_page.dart';
import 'package:vero360_app/features/Reels/Live/live_service.dart';
import 'package:vero360_app/features/Reels/Live/live_watch_page.dart';
import 'package:vero360_app/features/Reels/reel_model.dart';
import 'package:vero360_app/features/Reels/user_reels_page.dart';

/// Push tap for `type: reel_live` — the LIVE if it is still on, else the LIVE list.
Future<void> openLiveFromNotification(NavigatorState navigator, Map<String, dynamic> data) async {
  final liveId = (data['liveId'] ?? '').toString().trim();
  LiveStream? live;
  if (liveId.isNotEmpty) {
    try {
      final doc = await LiveService.instance.lives.doc(liveId).get();
      if (doc.exists) live = LiveStream.fromDoc(doc);
    } catch (_) {}
  }
  if (!navigator.mounted) return;
  if (live != null && live.isLive) {
    navigator.push(MaterialPageRoute<void>(builder: (_) => LiveWatchPage(live: live!)));
  } else {
    navigator.push(MaterialPageRoute<void>(builder: (_) => const LiveHubPage()));
  }
}

/// Push tap for `type: reel_posted` — plays that reel.
Future<void> openReelFromNotification(NavigatorState navigator, Map<String, dynamic> data) async {
  final reelId = (data['reelId'] ?? '').toString().trim();
  if (reelId.isEmpty) return;
  Reel? reel;
  try {
    final doc = await FirebaseFirestore.instance.collection('reels').doc(reelId).get();
    if (doc.exists) reel = Reel.fromDoc(doc);
  } catch (_) {}
  if (!navigator.mounted || reel == null || reel.hidden || reel.videoUrl.isEmpty) return;
  navigator.push(MaterialPageRoute<void>(
    builder: (_) => ReelViewerPage(reels: [reel!]),
  ));
}

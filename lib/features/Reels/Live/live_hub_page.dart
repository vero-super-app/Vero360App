import 'package:flutter/material.dart';
import 'package:vero360_app/features/Reels/Live/go_live_page.dart';
import 'package:vero360_app/features/Reels/Live/live_service.dart';
import 'package:vero360_app/features/Reels/Live/live_watch_page.dart';
import 'package:vero360_app/features/Reels/Live/live_widgets.dart';
import 'package:vero360_app/features/Reels/reel_feed_view.dart';

const _kInk = Color(0xFF1B1D22);

/// Who's live now, plus the Go LIVE entry.
class LiveHubPage extends StatelessWidget {
  const LiveHubPage({super.key});

  void _goLive(BuildContext context) {
    if (LiveService.instance.uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Sign in to go live.'),
        action: SnackBarAction(
          label: 'Sign in',
          onPressed: () => Navigator.of(context).pushNamed('/login'),
        ),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GoLivePage()));
  }

  void _watch(BuildContext context, LiveStream live) {
    if (LiveService.instance.uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Sign in to watch LIVE.'),
        action: SnackBarAction(
          label: 'Sign in',
          onPressed: () => Navigator.of(context).pushNamed('/login'),
        ),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LiveWatchPage(live: live)));
  }

  @override
  Widget build(BuildContext context) {
    final myUid = LiveService.instance.uid;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F7FB),
        foregroundColor: _kInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiveBadge(),
            SizedBox(width: 8),
            Text('Vero LIVE', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      ),
      body: StreamBuilder<List<LiveStream>>(
        stream: LiveService.instance.watchLiveNow(),
        builder: (context, snap) {
          final lives = (snap.data ?? const <LiveStream>[])
              .where((l) => l.hostId != myUid)
              .toList();
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _goLiveCard(context)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      const Text('Live now',
                          style: TextStyle(
                              color: _kInk, fontSize: 17, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 8),
                      if (lives.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: kLiveRed.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${lives.length}',
                              style: const TextStyle(
                                  color: kLiveRed, fontWeight: FontWeight.w900, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ),
              if (!snap.hasData)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: kLiveOrange)),
                )
              else if (lives.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: kLiveRed.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.sensors_rounded, color: kLiveRed, size: 38),
                        ),
                        const SizedBox(height: 16),
                        const Text('No one is live right now',
                            style: TextStyle(
                                color: _kInk, fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        const Text(
                          'Be the first: show your products, answer questions and sell live.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.68,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _LiveCard(
                        live: lives[i],
                        onTap: () => _watch(context, lives[i]),
                      ),
                      childCount: lives.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _goLiveCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: GestureDetector(
        onTap: () => _goLive(context),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [kLiveRed, Color(0xFFFF5E3A), kLiveOrange],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: kLiveRed.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.videocam_rounded, color: kLiveRed, size: 30),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Go LIVE',
                        style: TextStyle(
                            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                    SizedBox(height: 2),
                    Text('Stream to your followers and chat in real time',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.live, required this.onTap});

  final LiveStream live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A2D35), Color(0xFF15161A)],
                ),
              ),
            ),
            if (live.hostPhoto.startsWith('http'))
              Opacity(
                opacity: 0.55,
                child: Image.network(live.hostPhoto,
                    fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x55000000), Colors.transparent, Color(0xCC000000)],
                  stops: [0, 0.4, 1],
                ),
              ),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [kLiveRed, kLiveOrange]),
                ),
                child: ReelAvatar(url: live.hostPhoto, name: live.hostName, size: 64),
              ),
            ),
            const Positioned(top: 10, left: 10, child: LiveBadge(small: true)),
            Positioned(top: 8, right: 8, child: LiveViewerPill(count: live.viewerCount)),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    live.title.isEmpty ? '${live.hostName} is live' : live.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(live.hostName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                      if (live.hostIsMerchant) ...[
                        const SizedBox(width: 3),
                        const Icon(Icons.verified_rounded, size: 13, color: kLiveOrange),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

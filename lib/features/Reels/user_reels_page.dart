import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace_share_navigation.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:vero360_app/features/Reels/post_reel_page.dart';
import 'package:vero360_app/features/Reels/reel_feed_view.dart';
import 'package:vero360_app/features/Reels/reel_model.dart';
import 'package:vero360_app/features/Reels/reel_service.dart';

const _kOrange = Color(0xFFFF8A00);

/// Grid of one person's reels (also used for a merchant shop's reels).
class UserReelsPage extends StatefulWidget {
  const UserReelsPage({
    super.key,
    required this.ownerId,
    required this.ownerName,
    this.ownerPhoto = '',
    this.isMerchant = false,
  });

  final String ownerId;
  final String ownerName;
  final String ownerPhoto;

  /// Shows a "Visit shop" button. Leave false when opened from the shop page.
  final bool isMerchant;

  @override
  State<UserReelsPage> createState() => _UserReelsPageState();
}

class _UserReelsPageState extends State<UserReelsPage> {
  final _service = ReelService.instance;
  List<Reel>? _reels;
  String? _error;
  bool? _following;
  bool _followBusy = false;
  int _followers = 0;
  ReelProfile? _profile;
  List<ReelProduct>? _products;
  int _tab = 0;
  bool _bioOpen = false;

  bool get _isMine => FirebaseAuth.instance.currentUser?.uid == widget.ownerId;

  bool get _isMerchant =>
      widget.isMerchant ||
      (_profile?.isMerchant ?? false) ||
      (_reels?.any((r) => r.ownerIsMerchant) ?? false);

  String get _handle {
    final base = widget.ownerName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return '@${base.isEmpty ? 'vero360' : base}';
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final results = await Future.wait<Object>([
      _service.fetchProfile(widget.ownerId),
      if (!_isMine) _service.followingIds(),
    ]);
    if (!mounted) return;
    final profile = results[0] as ReelProfile;
    setState(() {
      _profile = profile;
      _followers = profile.followerCount;
      if (!_isMine) {
        _following = (results[1] as Set<String>).contains(widget.ownerId);
      }
    });
    if (_isMerchant) _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _service.productsOf(widget.ownerId);
      if (mounted) setState(() => _products = products);
    } catch (_) {
      if (mounted) setState(() => _products = const []);
    }
  }

  Future<void> _toggleFollow() async {
    if (_followBusy || _following == null) return;
    if (!_service.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Sign in to follow.'),
        action: SnackBarAction(
          label: 'Sign in',
          onPressed: () => Navigator.of(context).pushNamed('/login'),
        ),
      ));
      return;
    }
    final wasFollowing = _following!;
    if (wasFollowing) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Unfollow ${widget.ownerName}?'),
          content: const Text('Their reels will no longer appear in your Following feed.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Unfollow'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _followBusy = true;
      _following = !wasFollowing;
      _followers = (_followers + (wasFollowing ? -1 : 1)).clamp(0, 1 << 31);
    });
    try {
      if (wasFollowing) {
        await _service.unfollow(widget.ownerId);
      } else {
        await _service.follow(widget.ownerId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _following = wasFollowing;
        _followers = (_followers + (wasFollowing ? 1 : -1)).clamp(0, 1 << 31);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update follow. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final reels = await _service.fetchByOwner(widget.ownerId);
      if (mounted) setState(() => _reels = reels);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load reels');
    }
  }

  Future<void> _refresh() => Future.wait([_load(), _loadProfile()]);

  Future<void> _open(int index) async {
    final reels = _reels;
    if (reels == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReelViewerPage(reels: reels, initialIndex: index),
    ));
    if (mounted) _load();
  }

  void _visitShop() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MerchantProductsPage(
        merchantId: widget.ownerId,
        merchantName: widget.ownerName,
      ),
    ));
  }

  Future<void> _postReel() async {
    if (!_service.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Sign in to post a reel.'),
        action: SnackBarAction(
          label: 'Sign in',
          onPressed: () => Navigator.of(context).pushNamed('/login'),
        ),
      ));
      return;
    }
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PostReelPage()),
    );
    if (posted == true && mounted) _load();
  }

  Future<void> _openProduct(ReelProduct p) async {
    final ok = await MarketplaceShareNavigation.openFirestoreProduct(
      p.id,
      CartServiceProvider.getInstance(),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This product is no longer available')),
      );
    }
  }

  void _shareProfile() {
    final shop = _isMerchant ? ' shop' : '';
    SharePlus.instance.share(ShareParams(
      text: 'Check out ${widget.ownerName}$shop reels on Vero360 🎬',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final reels = _reels;
    final likes = reels?.fold<int>(0, (s, r) => s + r.likeCount) ?? 0;
    final showShopTab = _isMerchant;
    if (!showShopTab && _tab == 1) _tab = 0;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.ownerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
            if (_isMerchant) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified_rounded, size: 17, color: _kOrange),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Share profile',
            onPressed: _shareProfile,
            icon: const Icon(Icons.ios_share_rounded, size: 22),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _kOrange,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(likes)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabsHeader(
                selected: _tab,
                showShop: showShopTab,
                reelCount: reels?.length ?? 0,
                productCount: _products?.length,
                onSelect: (i) => setState(() => _tab = i),
              ),
            ),
            ..._tab == 0 ? _reelsSlivers(reels) : _productSlivers(),
          ],
        ),
      ),
    );
  }

  Widget _header(int likes) {
    final profile = _profile;
    final bio = profile?.bio.trim() ?? '';
    final location = profile?.location.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        children: [
          GestureDetector(
            onTap: _following == false ? _toggleFollow : null,
            child: SizedBox(
              width: 104,
              height: 108,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFFFB347), _kOrange, Color(0xFFFF5E3A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: ReelAvatar(
                          url: widget.ownerPhoto, name: widget.ownerName, size: 90),
                    ),
                  ),
                  if (_following == false)
                    Positioned(
                      bottom: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _kOrange,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _handle,
            style: const TextStyle(color: Colors.black54, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (_isMerchant) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storefront_rounded, size: 14, color: _kOrange),
                  SizedBox(width: 4),
                  Text('Vero360 Shop',
                      style: TextStyle(
                          color: _kOrange, fontSize: 12, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Stat(value: profile?.followingCount ?? 0, label: 'Following'),
              const _StatDivider(),
              _Stat(value: _followers, label: 'Followers'),
              const _StatDivider(),
              _Stat(value: likes, label: 'Likes'),
            ],
          ),
          const SizedBox(height: 16),
          _actionRow(),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => setState(() => _bioOpen = !_bioOpen),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  bio,
                  textAlign: TextAlign.center,
                  maxLines: _bioOpen ? 20 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _kInk, fontSize: 14, height: 1.4),
                ),
              ),
            ),
          ] else if (_isMine) ...[
            const SizedBox(height: 12),
            const Text(
              'Add a shop description in your profile so viewers know what you sell.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black38, fontSize: 12.5),
            ),
          ],
          if (location.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on_outlined, size: 15, color: Colors.black45),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionRow() {
    final buttons = <Widget>[];
    if (_isMine) {
      buttons.add(Expanded(
        child: _PillButton(
          icon: Icons.add_rounded,
          label: 'Post a reel',
          primary: true,
          onTap: _postReel,
        ),
      ));
      buttons.add(const SizedBox(width: 8));
      buttons.add(Expanded(
        child: _PillButton(
          icon: Icons.ios_share_rounded,
          label: 'Share profile',
          onTap: _shareProfile,
        ),
      ));
    } else {
      if (_following != null) {
        buttons.add(Expanded(
          child: _following!
              ? _PillButton(
                  icon: Icons.check_rounded,
                  label: 'Following',
                  onTap: _followBusy ? null : _toggleFollow,
                )
              : _PillButton(
                  icon: Icons.person_add_alt_1_rounded,
                  label: 'Follow',
                  primary: true,
                  onTap: _followBusy ? null : _toggleFollow,
                ),
        ));
      }
      if (_isMerchant) {
        if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 8));
        buttons.add(Expanded(
          child: _PillButton(
            icon: Icons.storefront_rounded,
            label: 'Visit shop',
            onTap: _visitShop,
          ),
        ));
      }
    }
    if (buttons.isEmpty) return const SizedBox(height: 46);
    return Row(children: buttons);
  }

  List<Widget> _reelsSlivers(List<Reel>? reels) {
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text(_error!)),
        ),
      ];
    }
    if (reels == null) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: _kOrange)),
        ),
      ];
    }
    if (reels.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyTab(
            icon: Icons.video_collection_outlined,
            text: _isMine ? 'Share your first reel' : 'No reels yet',
            action: _isMine ? ('Post a reel', _postReel) : null,
          ),
        ),
      ];
    }
    return [
      SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 9 / 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _ReelGridTile(reel: reels[i], onTap: () => _open(i)),
          childCount: reels.length,
        ),
      ),
    ];
  }

  List<Widget> _productSlivers() {
    final products = _products;
    if (products == null) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: _kOrange)),
        ),
      ];
    }
    if (products.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyTab(
            icon: Icons.shopping_bag_outlined,
            text: 'No products in this shop yet',
            action: null,
          ),
        ),
      ];
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return [
      SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.8,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final p = products[i];
              return GestureDetector(
                onTap: () => _openProduct(p),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFECEEF2)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: p.image.startsWith('http')
                            ? Image.network(
                                p.image,
                                fit: BoxFit.cover,
                                cacheWidth: (200 * dpr).round(),
                                errorBuilder: (_, _, _) => const _ProductFallback(),
                              )
                            : const _ProductFallback(),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        child: Text(
                          p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: _kInk, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            childCount: products.length,
          ),
        ),
      ),
    ];
  }
}

const _kInk = Color(0xFF1B1D22);

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          Text(reelCompact(value),
              style: const TextStyle(color: _kInk, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 18, color: const Color(0xFFE3E5EA));
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : _kInk;
    return Material(
      color: primary ? _kOrange : const Color(0xFFF2F3F5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 46,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({
    required this.selected,
    required this.showShop,
    required this.reelCount,
    required this.productCount,
    required this.onSelect,
  });

  final int selected;
  final bool showShop;
  final int reelCount;
  final int? productCount;
  final ValueChanged<int> onSelect;

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    Widget tab(int i, IconData icon, String label) {
      final on = selected == i;
      return Expanded(
        child: InkWell(
          onTap: () => onSelect(i),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: on ? _kInk : Colors.black38),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          color: on ? _kInk : Colors.black38,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5)),
                ],
              ),
              const SizedBox(height: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 2.5,
                width: on ? 44 : 0,
                decoration: BoxDecoration(
                  color: _kOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFECEEF2))),
      ),
      child: Row(
        children: [
          tab(0, Icons.grid_view_rounded, 'Reels $reelCount'),
          if (showShop)
            tab(1, Icons.shopping_bag_outlined,
                productCount == null ? 'Shop' : 'Shop $productCount'),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeader old) =>
      old.selected != selected ||
      old.showShop != showShop ||
      old.reelCount != reelCount ||
      old.productCount != productCount;
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.text, required this.action});

  final IconData icon;
  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.black26),
          const SizedBox(height: 12),
          Text(text,
              style: const TextStyle(
                  color: Colors.black54, fontSize: 15, fontWeight: FontWeight.w600)),
          if (action != null) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: action!.$2,
              style: FilledButton.styleFrom(
                backgroundColor: _kOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(action!.$1, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductFallback extends StatelessWidget {
  const _ProductFallback();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFFFF0D9),
        child: const Icon(Icons.shopping_bag_outlined, color: _kOrange, size: 32),
      );
}

class _ReelGridTile extends StatelessWidget {
  const _ReelGridTile({required this.reel, required this.onTap});

  final Reel reel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = reel.product?.image ?? '';
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2B2B2B), Color(0xFF111111)],
              ),
            ),
          ),
          if (image.startsWith('http'))
            Opacity(
              opacity: 0.55,
              child: Image.network(image, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
          if (reel.caption.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                reel.caption.trim(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          const Center(
            child: Icon(Icons.play_circle_outline, color: Colors.white70, size: 36),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Row(
              children: [
                const Icon(Icons.visibility_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 3),
                Text(reelCompact(reel.viewCount),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                const Spacer(),
                const Icon(Icons.favorite_rounded, color: Colors.white, size: 13),
                const SizedBox(width: 3),
                Text(reelCompact(reel.likeCount),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (reel.hidden || reel.reportCount >= ReelService.autoHideReports)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Under review',
                    style: TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-screen player opened from a reels grid.
class ReelViewerPage extends StatefulWidget {
  const ReelViewerPage({super.key, required this.reels, this.initialIndex = 0});

  final List<Reel> reels;
  final int initialIndex;

  @override
  State<ReelViewerPage> createState() => _ReelViewerPageState();
}

class _ReelViewerPageState extends State<ReelViewerPage> {
  late final List<Reel> _reels = List<Reel>.from(widget.reels);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ReelFeedView(
            reels: _reels,
            active: true,
            initialIndex: widget.initialIndex,
            bottomInset: MediaQuery.paddingOf(context).bottom,
            onReelRemoved: (id) {
              setState(() => _reels.removeWhere((r) => r.id == id));
              if (_reels.isEmpty) Navigator.of(context).maybePop();
            },
          ),
          SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}

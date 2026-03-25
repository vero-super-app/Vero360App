// Full-screen story viewer — one merchant's stories, 24h, caption, video, record viewers.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';

import 'package:vero360_app/Home/merchant_story_model.dart';
import 'package:vero360_app/Home/story_service.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/main_marketPlace.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/food.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/accomodation_mainpage.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/ride_share_map_screen.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';

class StoryViewerScreen extends StatefulWidget {
  final List<MerchantStoryGroup> groups;
  final int initialGroupIndex;

  const StoryViewerScreen({
    super.key,
    required this.groups,
    required this.initialGroupIndex,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  int _currentIndex = 0;
  late int _groupIndex;
  static const Duration _autoAdvance = Duration(seconds: 8);
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isPaused = false;
  late AnimationController _progressController;
  final StoryService _storyService = StoryService();

  MerchantStoryGroup get _currentGroup => widget.groups[_groupIndex];
  List<MerchantStoryItem> get _items => _currentGroup.items;

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex;
    _pageController = PageController();
    _progressController = AnimationController(
      vsync: this,
      duration: _autoAdvance,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _onAutoAdvance();
        }
      });
    _restartProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordViewForCurrentSlide());
  }

  void _recordViewForCurrentSlide() {
    final items = _items;
    if (_currentIndex < 0 || _currentIndex >= items.length) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final viewerName = user.displayName ?? user.email ?? 'Someone';
    _storyService.recordView(
      storyId: items[_currentIndex].storyId,
      viewerId: user.uid,
      viewerName: viewerName,
      viewerProfileImageUrl: user.photoURL,
    );
  }

  void _restartProgress() {
    if (_isPaused) {
      _progressController
        ..stop()
        ..reset();
      return;
    }
    _progressController
      ..stop()
      ..reset()
      ..forward();
  }

  void _onAutoAdvance() {
    if (!mounted) return;
    if (_currentIndex < _items.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _goNextStoryGroupOrClose();
    }
  }

  bool _allowTapAdvance() {
    final now = DateTime.now();
    if (now.difference(_lastTap).inMilliseconds < 320) return false;
    _lastTap = now;
    return true;
  }

  void _goNextStoryGroupOrClose() {
    if (_groupIndex < widget.groups.length - 1) {
      setState(() {
        _groupIndex++;
        _currentIndex = 0;
      });
      _pageController.jumpToPage(0);
      _restartProgress();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('No story', style: TextStyle(color: Colors.white))),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => _progressController.stop(),
        onLongPressEnd: (_) {
          if (!_isPaused) _progressController.forward();
        },
        onTapUp: (details) {
          if (!_allowTapAdvance()) return;
          final w = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < w * 0.25) {
            if (_currentIndex > 0) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          } else if (details.globalPosition.dx > w * 0.75) {
            if (_currentIndex < items.length - 1) {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            } else {
              _goNextStoryGroupOrClose();
            }
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              onPageChanged: (i) {
                setState(() => _currentIndex = i);
                _restartProgress();
                _recordViewForCurrentSlide();
              },
              itemBuilder: (context, i) {
                final item = items[i];
                return _StoryPage(item: item);
              },
            ),
            SafeArea(
              child: Column(
                children: [
                  _topBar(),
                  const SizedBox(height: 8),
                  _progressBars(items.length),
                ],
              ),
            ),
            Positioned(
              top: 56,
              right: 16,
              child: SafeArea(
                child: InkWell(
                  onTap: () {
                    setState(() => _isPaused = !_isPaused);
                    if (_isPaused) {
                      _progressController.stop();
                    } else {
                      _progressController.forward();
                    }
                  },
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: SafeArea(
                child: Center(
                  child: InkWell(
                    onTap: _showDetails,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MerchantProductsPage(
                    merchantId: _currentGroup.merchantId,
                    merchantName: _currentGroup.merchantName,
                  ),
                ),
              );
            },
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white24,
              child: _currentGroup.merchantImageUrl != null
                  ? ClipOval(
                      child: Image.network(
                        _currentGroup.merchantImageUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.store, color: Colors.white),
                      ),
                    )
                  : const Icon(Icons.store, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _currentGroup.merchantName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                _timeAgoLabel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressBars(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AnimatedBuilder(
        animation: _progressController,
        builder: (context, _) {
          return Row(
            children: List.generate(count, (i) {
              final isPast = i < _currentIndex;
              final isCurrent = i == _currentIndex;
              final value = isPast
                  ? 1.0
                  : isCurrent
                      ? _progressController.value
                      : 0.0;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: value.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _timeAgoLabel() {
    if (_items.isEmpty) {
      return const SizedBox.shrink();
    }
    final item =
        _items[_currentIndex.clamp(0, _items.length - 1)];
    final now = DateTime.now();
    final diff = now.difference(item.createdAt);
    String text;
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes.clamp(1, 59);
      text = '${m}m ago';
    } else if (diff.inHours < 24) {
      final h = diff.inHours;
      text = '${h}h ago';
    } else {
      final d = diff.inDays;
      text = '${d}d ago';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showDetails() {
    if (_items.isEmpty) return;
    final item = _items[_currentIndex.clamp(0, _items.length - 1)];

    final type = (item.serviceType ?? 'marketplace').toLowerCase();
    String primaryLabel;
    VoidCallback onPrimary;

    switch (type) {
      case 'accommodation':
        primaryLabel = 'Book now';
        onPrimary = () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AccommodationMainPage(),
            ),
          );
        };
        break;
      case 'ride':
      case 'taxi':
      case 'ride_share':
        primaryLabel = 'Book now';
        onPrimary = () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const RideShareMapScreen(),
            ),
          );
        };
        break;
      case 'food':
        primaryLabel = 'Order now';
        onPrimary = () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const FoodPage(),
            ),
          );
        };
        break;
      default:
        primaryLabel = 'Buy now ';
        onPrimary = () {
          Navigator.of(context).pop();
          final cart = CartServiceProvider.getInstance();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MarketPage(cartService: cart),
            ),
          );
        };
        break;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text(
                item.title?.isNotEmpty == true ? item.title! : _currentGroup.merchantName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              if (item.price != null)
                Text(
                  'MWK ${item.price!.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF8A00),
                  ),
                ),
              const SizedBox(height: 6),
              if (item.description != null && item.description!.isNotEmpty)
                Text(
                  item.description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                )
              else if (item.caption != null && item.caption!.trim().isNotEmpty)
                Text(
                  item.caption!,
                  style: const TextStyle(fontSize: 14),
                )
              else
                const Text(
                  'Open the relevant service to book or purchase this item.',
                  style: TextStyle(fontSize: 13),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onPrimary,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8A00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        primaryLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StoryPage extends StatefulWidget {
  final MerchantStoryItem item;

  const _StoryPage({required this.item});

  @override
  State<_StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<_StoryPage> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.item.mediaType == 'video' && widget.item.mediaUrl.trim().isNotEmpty) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.item.mediaUrl))
        ..initialize().then((_) {
          if (mounted) {
            _videoController!.setLooping(true);
            _videoController!.play();
            setState(() {});
          }
        }).catchError((_) {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildMedia(item),
        if (item.caption != null && item.caption!.trim().isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 40,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  item.caption!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMedia(MerchantStoryItem item) {
    if (item.mediaType == 'video') {
      if (_videoController == null) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      if (!_videoController!.value.isInitialized) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      return Center(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
      );
    }
    if (item.hasInlineImage && item.imageBase64 != null) {
      try {
        final bytes = base64Decode(item.imageBase64!);
        return Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Text('Unable to load', style: TextStyle(color: Colors.white)),
            ),
          ),
        );
      } catch (_) {
        return const Center(
          child: Text('Unable to load', style: TextStyle(color: Colors.white)),
        );
      }
    }
    if (item.mediaUrl.isNotEmpty) {
      return Center(
        child: Image.network(
          item.mediaUrl,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Text('Unable to load', style: TextStyle(color: Colors.white)),
          ),
        ),
      );
    }
    return const Center(
      child: Text('No media', style: TextStyle(color: Colors.white)),
    );
  }
}

// Full-screen story viewer — one merchant's stories, 24h, merchant name shown.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:vero360_app/Home/merchant_story_model.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/main_marketPlace.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/food.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/accomodation_mainpage.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/ride_share_map_screen.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';

class StoryViewerScreen extends StatefulWidget {
  final MerchantStoryGroup group;

  const StoryViewerScreen({super.key, required this.group});

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  Timer? _timer;
  static const Duration _autoAdvance = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(_autoAdvance, () {
      if (!mounted) return;
      if (_currentIndex < widget.group.items.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.group.items;
    if (items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('No story', style: TextStyle(color: Colors.white))),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (details) {
          final w = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < w * 0.35) {
            if (_currentIndex > 0) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          } else if (details.globalPosition.dx > w * 0.65) {
            if (_currentIndex < items.length - 1) {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            } else {
              Navigator.of(context).pop();
            }
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: items.length,
              onPageChanged: (i) {
                setState(() => _currentIndex = i);
                _startTimer();
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
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white24,
            child: widget.group.merchantImageUrl != null
                ? ClipOval(
                    child: Image.network(
                      widget.group.merchantImageUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.store, color: Colors.white),
                    ),
                  )
                : const Icon(Icons.store, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.group.merchantName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '24h',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
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
      child: Row(
        children: List.generate(count, (i) {
          final past = i < _currentIndex;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              height: 3,
              decoration: BoxDecoration(
                color: past ? Colors.white : Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _showDetails() {
    if (widget.group.items.isEmpty) return;
    final item = widget.group.items[_currentIndex.clamp(0, widget.group.items.length - 1)];

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
                item.title?.isNotEmpty == true ? item.title! : widget.group.merchantName,
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

class _StoryPage extends StatelessWidget {
  final MerchantStoryItem item;

  const _StoryPage({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.mediaType == 'video') {
      return const Center(
        child: Text('Video stories coming soon', style: TextStyle(color: Colors.white)),
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
      child: Text('No image', style: TextStyle(color: Colors.white)),
    );
  }
}

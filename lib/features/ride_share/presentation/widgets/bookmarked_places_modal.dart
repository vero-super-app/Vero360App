import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/destination_search_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

/// Saved places sheet — same tile language as [DestinationSearchScreen].
class BookmarkedPlacesModal extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  /// When true, tapping a place sets it as the ride dropoff.
  final bool selectAsDropoff;

  const BookmarkedPlacesModal({
    required this.onClose,
    this.selectAsDropoff = true,
    super.key,
  });

  /// Opens the sheet as a proper modal (preferred over nesting in a panel).
  static Future<void> show(
    BuildContext context, {
    bool selectAsDropoff = true,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (sheetContext) => BookmarkedPlacesModal(
        selectAsDropoff: selectAsDropoff,
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  @override
  ConsumerState<BookmarkedPlacesModal> createState() =>
      _BookmarkedPlacesModalState();
}

class _BookmarkedPlacesModalState extends ConsumerState<BookmarkedPlacesModal> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await BookmarkedPlacesManager.loadAndSet(ref);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _selectPlace(Place place) async {
    if (widget.selectAsDropoff) {
      ref.read(selectedDropoffPlaceProvider.notifier).state = place;
      await RecentPlacesManager.addPlace(ref, place);
    } else {
      ref.read(selectedPickupPlaceProvider.notifier).state = place;
    }
    if (!mounted) return;
    widget.onClose();
  }

  Future<void> _setHomeOrWork(PlaceType type) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DestinationSearchScreen(saveAsType: type),
      ),
    );
    await _reload();
  }

  Future<void> _addFavorite() async {
    final place = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (_) => const DestinationSearchScreen(returnPlaceOnly: true),
      ),
    );
    if (place == null) return;
    await BookmarkedPlacesManager.addPlace(
      ref,
      place.copyWith(type: PlaceType.FAVORITE, isBookmarked: true),
    );
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Place saved'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _removePlace(Place place) async {
    await BookmarkedPlacesManager.removePlace(ref, place.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final bookmarked = ref.watch(bookmarkedPlacesProvider);
    Place? home;
    Place? work;
    final favorites = <Place>[];

    for (final p in bookmarked) {
      if (p.type == PlaceType.HOME) {
        home ??= p;
      } else if (p.type == PlaceType.WORK) {
        work ??= p;
      } else {
        favorites.add(p);
      }
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          color: RideShareColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: RideShareColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Saved places',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: RideShareColors.titleText,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close),
                        color: RideShareColors.titleText,
                        style: IconButton.styleFrom(
                          backgroundColor: RideShareColors.surfaceContainerLow,
                          shape: const CircleBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(
                          RideShareColors.primary,
                        ),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
                      children: [
                        _SavedPlaceTile(
                          icon: home != null ? Icons.home : Icons.home_outlined,
                          title: 'Home',
                          subtitle: home?.address ?? 'Add your home address',
                          onTap: () {
                            final savedHome = home;
                            if (savedHome != null) {
                              _selectPlace(savedHome);
                            } else {
                              _setHomeOrWork(PlaceType.HOME);
                            }
                          },
                          onLongPress: () => _setHomeOrWork(PlaceType.HOME),
                          onRemove: home == null
                              ? null
                              : () {
                                  final savedHome = home;
                                  if (savedHome != null) {
                                    _removePlace(savedHome);
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        _SavedPlaceTile(
                          icon: work != null ? Icons.work : Icons.work_outline,
                          title: 'Work',
                          subtitle: work?.address ?? 'Add your work address',
                          onTap: () {
                            final savedWork = work;
                            if (savedWork != null) {
                              _selectPlace(savedWork);
                            } else {
                              _setHomeOrWork(PlaceType.WORK);
                            }
                          },
                          onLongPress: () => _setHomeOrWork(PlaceType.WORK),
                          onRemove: work == null
                              ? null
                              : () {
                                  final savedWork = work;
                                  if (savedWork != null) {
                                    _removePlace(savedWork);
                                  }
                                },
                        ),
                        if (favorites.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Text(
                            'Favourites',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: RideShareColors.titleText,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...favorites.map(
                            (place) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _SavedPlaceTile(
                                icon: Icons.star,
                                title: place.name,
                                subtitle: place.address,
                                onTap: () => _selectPlace(place),
                                onRemove: () => _removePlace(place),
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 28),
                          Icon(
                            Icons.bookmark_outline,
                            size: 48,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            home == null && work == null
                                ? 'No saved places yet'
                                : 'No favourites yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Save Home, Work, or favourites for quick access',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: _addFavorite,
                            icon: const Icon(Icons.add),
                            label: const Text('Add favourite'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: RideShareColors.primary,
                              side: const BorderSide(
                                color: RideShareColors.primary,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Same visual language as destination search shortcut tiles.
class _SavedPlaceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRemove;

  const _SavedPlaceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RideShareColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: RideShareColors.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: RideShareColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: RideShareColors.primary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: RideShareColors.titleText,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: RideShareColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: RideShareColors.onSurfaceVariant,
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                )
              else
                const Icon(Icons.chevron_right, color: RideShareColors.outline),
            ],
          ),
        ),
      ),
    );
  }
}

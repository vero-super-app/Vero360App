import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/destination_search_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/map_location_picker_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

class BookmarkedPlacesModal extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  /// When true, tapping a place sets it as the ride dropoff.
  final bool selectAsDropoff;

  const BookmarkedPlacesModal({
    required this.onClose,
    this.selectAsDropoff = true,
    super.key,
  });

  @override
  ConsumerState<BookmarkedPlacesModal> createState() =>
      _BookmarkedPlacesModalState();
}

class _BookmarkedPlacesModalState extends ConsumerState<BookmarkedPlacesModal> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BookmarkedPlacesManager.loadAndSet(ref);
    });
  }

  Future<void> _addPlace() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.search, color: RideShareColors.primary),
              title: const Text('Search for a place'),
              onTap: () => Navigator.pop(ctx, 'search'),
            ),
            ListTile(
              leading: const Icon(Icons.map, color: RideShareColors.primary),
              title: const Text('Pick on map'),
              onTap: () => Navigator.pop(ctx, 'map'),
            ),
            ListTile(
              leading: const Icon(Icons.home, color: RideShareColors.primary),
              title: const Text('Set Home'),
              onTap: () => Navigator.pop(ctx, 'home'),
            ),
            ListTile(
              leading: const Icon(Icons.work, color: RideShareColors.primary),
              title: const Text('Set Work'),
              onTap: () => Navigator.pop(ctx, 'work'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    switch (choice) {
      case 'search':
        final place = await Navigator.push<Place>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const DestinationSearchScreen(returnPlaceOnly: true),
          ),
        );
        if (place != null) {
          await BookmarkedPlacesManager.addPlace(
            ref,
            place.copyWith(type: PlaceType.FAVORITE, isBookmarked: true),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Place saved'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      case 'map':
        final picked = await Navigator.push<Place>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const MapLocationPickerScreen(selectAsDropoff: false),
          ),
        );
        if (picked != null) {
          await BookmarkedPlacesManager.addPlace(
            ref,
            picked.copyWith(type: PlaceType.FAVORITE, isBookmarked: true),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Place saved'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      case 'home':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const DestinationSearchScreen(saveAsType: PlaceType.HOME),
          ),
        );
      case 'work':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const DestinationSearchScreen(saveAsType: PlaceType.WORK),
          ),
        );
    }
  }

  void _selectPlace(Place place) {
    if (widget.selectAsDropoff) {
      RecentPlacesManager.addPlace(ref, place);
      ref.read(selectedDropoffPlaceProvider.notifier).state = place;
    } else {
      ref.read(selectedPickupPlaceProvider.notifier).state = place;
    }
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final bookmarkedPlaces = ref.watch(bookmarkedPlacesProvider);
    final selectedDropoff = ref.watch(selectedDropoffPlaceProvider);

    return Material(
      color: Colors.transparent,
      child: Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Saved Places',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: bookmarkedPlaces.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: bookmarkedPlaces.length,
                            itemBuilder: (context, index) {
                              final place = bookmarkedPlaces[index];
                              final isSelected =
                                  selectedDropoff?.id == place.id;
                              return _buildPlaceTile(
                                place: place,
                                isSelected: isSelected,
                                onSelect: () => _selectPlace(place),
                                onDelete: () {
                                  BookmarkedPlacesManager.removePlace(
                                    ref,
                                    place.id,
                                  );
                                },
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _addPlace,
                        icon: const Icon(Icons.add),
                        label: const Text('Add New Place'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: RideShareColors.primary,
                          side: const BorderSide(color: RideShareColors.primary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No saved places yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Save Home, Work, or favourites for quick access',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceTile({
    required Place place,
    required bool isSelected,
    required VoidCallback onSelect,
    required VoidCallback onDelete,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: RideShareColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getPlaceIcon(place.type),
          color: RideShareColors.primary,
        ),
      ),
      title: Text(
        place.name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        place.address,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, color: Colors.red, size: 18),
                SizedBox(width: 8),
                Text('Delete'),
              ],
            ),
          ),
        ],
      ),
      onTap: onSelect,
      selected: isSelected,
      selectedTileColor: RideShareColors.primary.withValues(alpha: 0.05),
    );
  }

  IconData _getPlaceIcon(PlaceType type) {
    switch (type) {
      case PlaceType.HOME:
        return Icons.home;
      case PlaceType.WORK:
        return Icons.business;
      case PlaceType.FAVORITE:
        return Icons.star;
      case PlaceType.RECENT:
        return Icons.history;
    }
  }
}

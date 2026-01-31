import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/models/place_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';

class BookmarkedPlacesModal extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const BookmarkedPlacesModal({
    required this.onClose,
    super.key,
  });

  @override
  ConsumerState<BookmarkedPlacesModal> createState() =>
      _BookmarkedPlacesModalState();
}

class _BookmarkedPlacesModalState extends ConsumerState<BookmarkedPlacesModal> {
  @override
  Widget build(BuildContext context) {
    final bookmarkedPlaces = ref.watch(bookmarkedPlacesProvider);
    final selectedPlace = ref.watch(selectedPickupPlaceProvider);

    return GestureDetector(
      onTap: () {
        if (selectedPlace == null) {
          widget.onClose();
        }
      },
      child: Container(
        color: Colors.black.withOpacity(0.3),
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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

                  // Places list
                  Expanded(
                    child: bookmarkedPlaces.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: bookmarkedPlaces.length,
                            itemBuilder: (context, index) {
                              final place = bookmarkedPlaces[index];
                              final isSelected = selectedPlace?.id == place.id;

                              return _buildPlaceTile(
                                place: place,
                                isSelected: isSelected,
                                onSelect: () {
                                  ref
                                      .read(
                                          selectedPickupPlaceProvider.notifier)
                                      .state = place;
                                  widget.onClose();
                                },
                                onDelete: () {
                                  BookmarkedPlacesManager.removePlace(
                                      ref, place.id);
                                },
                              );
                            },
                          ),
                  ),

                  // Add new place button
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // TODO: Open add new place dialog
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add New Place'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Color(0xFFFF8A00),
                          ),
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
            'Save your favorite locations for quick access',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
            ),
          ),
        ],
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
          color: const Color(0xFFFF8A00).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getPlaceIcon(place.type),
          color: const Color(0xFFFF8A00),
        ),
      ),
      title: Text(
        place.name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle:
          Text(place.address, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'delete') {
            onDelete();
          }
        },
        itemBuilder: (BuildContext context) => [
          const PopupMenuItem<String>(
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
      selectedTileColor: const Color(0xFFFF8A00).withOpacity(0.05),
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

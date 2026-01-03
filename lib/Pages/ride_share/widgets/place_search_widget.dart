import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/providers/ride_share_provider.dart';

class PlaceSearchWidget extends ConsumerStatefulWidget {
  final TextEditingController searchController;
  final VoidCallback onToggleBookmarkedPlaces;

  const PlaceSearchWidget({
    required this.searchController,
    required this.onToggleBookmarkedPlaces,
    Key? key,
  }) : super(key: key);

  @override
  ConsumerState<PlaceSearchWidget> createState() => _PlaceSearchWidgetState();
}

class _PlaceSearchWidgetState extends ConsumerState<PlaceSearchWidget> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(placeSearchProvider(_searchQuery));
    final selectedPlace = ref.watch(selectedPickupPlaceProvider);

    return Column(
      children: [
        // Search bar
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.searchController,
                  decoration: InputDecoration(
                    hintText: 'Search destination...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    prefixIcon: const Icon(
                      Icons.location_on,
                      color: Color(0xFFFF8A00),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: const Icon(
                    Icons.bookmark_outline,
                    color: Color(0xFFFF8A00),
                  ),
                  onPressed: widget.onToggleBookmarkedPlaces,
                  tooltip: 'Bookmarked places',
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Search results
        if (_searchQuery.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 300),
            child: searchResults.when(
              data: (results) {
                if (results.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.location_off, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          'No results for "$_searchQuery"',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Search must be within Malawi',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final place = results[index];
                    final isSelected = selectedPlace?.id == place.id;

                    return ListTile(
                      leading: const Icon(Icons.location_on),
                      title: Text(
                        place.name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(place.address),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: Color(0xFFFF8A00),
                            )
                          : null,
                      onTap: () {
                        ref
                            .read(selectedPickupPlaceProvider.notifier)
                            .state = place;
                        widget.searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    );
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
              error: (error, stackTrace) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(height: 8),
                    Text(
                      'Error searching places',
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    widget.searchController.dispose();
    super.dispose();
  }
}

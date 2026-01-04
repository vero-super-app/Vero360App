import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/providers/ride_share_provider.dart';
import 'package:vero360_app/models/place_model.dart';

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
  void dispose() {
    widget.searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(serpapiPlacesAutocompleteProvider(_searchQuery));
    final selectedDropoffPlace = ref.watch(selectedDropoffPlaceProvider);

    return Column(
      children: [
        // Search bar for destination
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
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
                  onChanged: _onSearchChanged,
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

        // Minimum length hint
        if (_searchQuery.isNotEmpty && _searchQuery.length < 4)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Type at least 4 characters to search',
                    style: TextStyle(color: Colors.orange[700], fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // Search results
        if (_searchQuery.isNotEmpty && _searchQuery.length >= 4)
          SingleChildScrollView(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              constraints: const BoxConstraints(maxHeight: 300),
              child: searchResults.when(
              data: (predictions) {
                if (predictions.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.location_off, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          'No results found for "$_searchQuery"',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Searching in Malawi. Try a different search term',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: predictions.length,
                  itemBuilder: (context, index) {
                    final prediction = predictions[index];

                    return ListTile(
                      leading: const Icon(Icons.location_on),
                      title: Text(
                        prediction.mainText,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        prediction.secondaryText.isNotEmpty
                            ? prediction.secondaryText
                            : prediction.fullText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        // Use coordinates from prediction (already available from search)
                        if (prediction.latitude != null && prediction.longitude != null) {
                          final place = Place(
                            id: prediction.placeId,
                            name: prediction.mainText,
                            address: prediction.fullText,
                            latitude: prediction.latitude!,
                            longitude: prediction.longitude!,
                            type: PlaceType.RECENT,
                          );
                          
                          ref.read(selectedDropoffPlaceProvider.notifier).state = place;
                          widget.searchController.clear();
                          
                          setState(() {
                            _searchQuery = '';
                          });
                        } else {
                          // Fallback: show error if coordinates not available
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Unable to get location coordinates')),
                          );
                        }
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
                    const SizedBox(height: 4),
                    Text(
                      error.toString(),
                      style: TextStyle(color: Colors.red[600], fontSize: 11),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),
      ],
    );
  }
}

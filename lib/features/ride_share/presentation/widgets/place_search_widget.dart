import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'skeleton_loader.dart';

class PlaceSearchWidget extends ConsumerStatefulWidget {
  final TextEditingController searchController;
  final FocusNode? focusNode;
  final VoidCallback onToggleBookmarkedPlaces;
  final bool readOnly;
  final VoidCallback? onTap;

  const PlaceSearchWidget({
    required this.searchController,
    this.focusNode,
    required this.onToggleBookmarkedPlaces,
    this.readOnly = false,
    this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  ConsumerState<PlaceSearchWidget> createState() => _PlaceSearchWidgetState();
}

class _PlaceSearchWidgetState extends ConsumerState<PlaceSearchWidget> {
  String _searchQuery = '';
  bool _isFocused = false;

  @override
  void dispose() {
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchResults =
        ref.watch(serpapiPlacesAutocompleteProvider(_searchQuery));

    return Column(
      children: [
        // Modern search bar with glassmorphism effect
        Focus(
          onFocusChange: (focused) {
            setState(() => _isFocused = focused);
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isFocused ? const Color(0xFFFF8A00) : Colors.grey[200]!,
                width: _isFocused ? 2 : 1,
              ),
              boxShadow: [
                if (_isFocused)
                  BoxShadow(
                    color: const Color(0xFFFF8A00).withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                else
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Icon(
                    Icons.location_on_rounded,
                    color:
                        _isFocused ? const Color(0xFFFF8A00) : Colors.grey[400],
                    size: 22,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: widget.searchController,
                    focusNode: widget.focusNode,
                    readOnly: widget.readOnly,
                    onTap: widget.onTap,
                    decoration: InputDecoration(
                      hintText: 'Where to?',
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    onChanged: widget.readOnly ? null : _onSearchChanged,
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: Colors.grey[600],
                      onPressed: () {
                        widget.searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    icon: const Icon(Icons.bookmark_outline, size: 22),
                    color:
                        _isFocused ? const Color(0xFFFF8A00) : Colors.grey[600],
                    onPressed: widget.onToggleBookmarkedPlaces,
                    tooltip: 'Saved places',
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Minimum length hint
        if (_searchQuery.isNotEmpty && _searchQuery.length < 4)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange[600], size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Type at least 4 characters',
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
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              constraints: const BoxConstraints(maxHeight: 320),
              child: searchResults.when(
                data: (predictions) {
                  if (predictions.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: predictions.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Colors.grey[200],
                      indent: 52,
                    ),
                    itemBuilder: (context, index) {
                      final prediction = predictions[index];

                      return _buildResultTile(prediction, context);
                    },
                  );
                },
                loading: () => Padding(
                  padding: const EdgeInsets.all(12),
                  child: SearchResultSkeletonLoader(),
                ),
                error: (error, stackTrace) {
                  if (kDebugMode) {
                    debugPrint('[PlaceSearch] Error: $error');
                    debugPrint('[PlaceSearch] StackTrace: $stackTrace');
                  }
                  return _buildErrorState(error);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResultTile(dynamic prediction, BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          // Fetch place details to get coordinates
          final placeDetails =
              await ref.read(placeDetailsProvider(prediction.placeId).future);

          final geometry = placeDetails['geometry'] as Map<String, dynamic>?;
          final location = geometry?['location'] as Map<String, dynamic>?;

          if (location != null) {
            final place = Place(
              id: prediction.placeId,
              name: prediction.mainText,
              address: prediction.fullText,
              latitude: (location['lat'] as num?)?.toDouble() ?? 0.0,
              longitude: (location['lng'] as num?)?.toDouble() ?? 0.0,
              type: PlaceType.RECENT,
            );

            ref.read(selectedDropoffPlaceProvider.notifier).state = place;
            widget.searchController.clear();

            setState(() {
              _searchQuery = '';
            });
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Unable to get location coordinates'),
                  behavior: SnackBarBehavior.floating,
                  margin: EdgeInsets.all(16),
                ),
              );
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A00).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Color(0xFFFF8A00),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prediction.mainText,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      prediction.secondaryText.isNotEmpty
                          ? prediction.secondaryText
                          : prediction.fullText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_off_outlined, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'No results found',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try searching for a different location',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    String errorMessage = 'Please try again';
    String errorTitle = 'Search error';

    if (error.toString().contains('API key') || error.toString().contains('not configured')) {
      errorTitle = 'Configuration Required';
      errorMessage = 'Google Maps API key not configured.\nRun: flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key';
    } else if (error.toString().contains('billing')) {
      errorTitle = 'Billing Not Enabled';
      errorMessage = 'Enable billing at Google Cloud Console';
    } else if (error.toString().contains('REQUEST_DENIED')) {
      errorTitle = 'API Access Denied';
      errorMessage = 'Check your API key permissions';
    } else if (error.toString().contains('Network') || error.toString().contains('connection')) {
      errorTitle = 'Network Error';
      errorMessage = 'Check your internet connection';
    } else if (error.toString().contains('ZERO_RESULTS')) {
      errorTitle = 'No Results';
      errorMessage = 'Try searching with different keywords';
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Colors.red[400], size: 40),
          const SizedBox(height: 12),
          Text(
            errorTitle,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            errorMessage,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
            textAlign: TextAlign.center,
          ),
          if (kDebugMode)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error.toString(),
                style: TextStyle(
                  color: Colors.red[300],
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

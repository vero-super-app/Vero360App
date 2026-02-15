import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';

class DestinationSearchScreen extends ConsumerStatefulWidget {
  const DestinationSearchScreen({super.key});

  @override
  ConsumerState<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState
    extends ConsumerState<DestinationSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RecentPlacesManager.loadAndSet(ref);
    });
    // Auto-focus the search field when screen opens
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && !_searchFocusNode.hasFocus) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _showLoadingAndReturn() async {
    // Show loading overlay for 2 seconds
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A00)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Fetching routes...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );

    // Wait for 2 seconds
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      // Close loading dialog
      Navigator.pop(context);
      // Pop destination search screen and return to map
      Navigator.pop(context);
    }
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.arrow_back_ios_new,
          color: Colors.black87,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildRecentPlacesSection() {
    final recentPlaces = ref.watch(recentPlacesProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Colors.transparent,
            width: MediaQuery.of(context).size.width,
            child: Center(
              child: Text(
                'Recent Places',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (recentPlaces.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No recent searches yet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                      ),
                ),
              ),
            )
          else
            ...recentPlaces.map((place) => _buildRecentPlaceItem(place)),
        ],
      ),
    );
  }

  Widget _buildRecentPlaceItem(Place place) {
    return GestureDetector(
      onTap: () {
        ref.read(selectedDropoffPlaceProvider.notifier).state = place;
        _showLoadingAndReturn();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8A00).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.history,
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
                    place.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    place.address,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[500],
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context);
        return false;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  _buildBackButton(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Where are you going?',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            // Search field at top
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _CustomPlaceSearchWidget(
                searchController: _searchController,
                focusNode: _searchFocusNode,
                onLocationSelected: (place) {
                  RecentPlacesManager.addPlace(ref, place);
                  ref.read(selectedDropoffPlaceProvider.notifier).state = place;
                  _showLoadingAndReturn();
                },
              ),
            ),
            // Recent places shown when search is empty
            Expanded(
              child: Container(
                color: Colors.grey[50],
                child: _buildRecentPlacesSection(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomPlaceSearchWidget extends ConsumerStatefulWidget {
  final TextEditingController searchController;
  final FocusNode focusNode;
  final Function(Place) onLocationSelected;

  const _CustomPlaceSearchWidget({
    required this.searchController,
    required this.focusNode,
    required this.onLocationSelected,
  });

  @override
  ConsumerState<_CustomPlaceSearchWidget> createState() =>
      _CustomPlaceSearchWidgetState();
}

class _CustomPlaceSearchWidgetState
    extends ConsumerState<_CustomPlaceSearchWidget> {
  String _searchQuery = '';
  bool _isFocused = false;

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
        // Modern search bar
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
                    onChanged: _onSearchChanged,
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Search results dropdown
        if (_searchQuery.isNotEmpty && _searchQuery.length >= 4)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 300),
            child: searchResults.when(
              data: (predictions) {
                if (predictions.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No results found',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: predictions.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: Colors.grey[200],
                  ),
                  itemBuilder: (context, index) {
                    final prediction = predictions[index];

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          final placeDetails = await ref.read(
                              placeDetailsProvider(prediction.placeId).future);
                          final geometry =
                              placeDetails['geometry'] as Map<String, dynamic>?;
                          final location =
                              geometry?['location'] as Map<String, dynamic>?;

                          if (location != null) {
                            final place = Place(
                              id: prediction.placeId,
                              name: prediction.mainText,
                              address: prediction.fullText,
                              latitude:
                                  (location['lat'] as num?)?.toDouble() ?? 0.0,
                              longitude:
                                  (location['lng'] as num?)?.toDouble() ?? 0.0,
                              type: PlaceType.RECENT,
                            );

                            widget.onLocationSelected(place);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFFFF8A00).withOpacity(0.1),
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
                  },
                );
              },
              loading: () => Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 100,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
                    ),
                  ),
                ),
              ),
              error: (error, stackTrace) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error loading results',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

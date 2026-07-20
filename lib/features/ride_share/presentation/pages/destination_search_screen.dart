import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/map_location_picker_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

class DestinationSearchScreen extends ConsumerStatefulWidget {
  /// When set, selecting a place saves Home/Work instead of booking dropoff.
  final PlaceType? saveAsType;

  /// When true, selecting a place only returns it (no dropoff / recent side effects).
  final bool returnPlaceOnly;

  const DestinationSearchScreen({
    this.saveAsType,
    this.returnPlaceOnly = false,
    super.key,
  });

  @override
  ConsumerState<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState
    extends ConsumerState<DestinationSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool get _isSaveMode =>
      widget.saveAsType == PlaceType.HOME || widget.saveAsType == PlaceType.WORK;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RecentPlacesManager.loadAndSet(ref);
      BookmarkedPlacesManager.loadAndSet(ref);
    });
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

  Future<void> _selectPlace(Place place) async {
    if (_isSaveMode) {
      await BookmarkedPlacesManager.setHomeOrWork(
        ref,
        place,
        widget.saveAsType!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.saveAsType == PlaceType.HOME
                  ? 'Home saved'
                  : 'Work saved',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, place);
      }
      return;
    }

    if (widget.returnPlaceOnly) {
      if (mounted) Navigator.pop(context, place);
      return;
    }

    await RecentPlacesManager.addPlace(ref, place);
    ref.read(selectedDropoffPlaceProvider.notifier).state = place;
    if (mounted) Navigator.pop(context, place);
  }

  Future<void> _openMapPicker({PlaceType? saveAs}) async {
    final result = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
          saveAsType: saveAs ?? widget.saveAsType,
        ),
      ),
    );
    if (result != null && mounted && !_isSaveMode && saveAs == null) {
      Navigator.pop(context, result);
    } else if (result != null && mounted && (_isSaveMode || saveAs != null)) {
      // Home/Work already saved by picker; refresh and close if we were in save mode
      if (_isSaveMode) Navigator.pop(context, result);
    }
  }

  Future<void> _startSaveHomeOrWork(PlaceType type) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DestinationSearchScreen(saveAsType: type),
      ),
    );
  }

  void _clearRecentPlaces() {
    RecentPlacesManager.clearAll(ref);
  }

  String get _title {
    switch (widget.saveAsType) {
      case PlaceType.HOME:
        return 'Set Home';
      case PlaceType.WORK:
        return 'Set Work';
      default:
        return 'Search';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickupAsync = ref.watch(pickupDisplayProvider);
    final profilePictureUrl = pickupAsync.maybeWhen(
      data: (p) => p.profilePictureUrl,
      orElse: () => '',
    );

    return Scaffold(
      backgroundColor: RideShareColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    color: RideShareColors.titleText,
                    style: IconButton.styleFrom(
                      backgroundColor: RideShareColors.surfaceContainerLow,
                      shape: const CircleBorder(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: RideShareColors.titleText,
                    ),
                  ),
                  const Spacer(),
                  _ProfileAvatar(url: profilePictureUrl),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isSaveMode)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Search for an address or pick on the map',
                          style: TextStyle(
                            color: RideShareColors.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    _SearchInput(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onPlaceSelected: _selectPlace,
                      confirmLabel: _isSaveMode ? 'Save' : null,
                    ),
                    const SizedBox(height: 24),
                    if (!_isSaveMode)
                      _ShortcutsSection(
                        onPlaceSelected: _selectPlace,
                        onSetOnMap: () => _openMapPicker(),
                        onSetHome: () => _startSaveHomeOrWork(PlaceType.HOME),
                        onSetWork: () => _startSaveHomeOrWork(PlaceType.WORK),
                      )
                    else
                      _ShortcutTile(
                        icon: Icons.map,
                        iconBg: RideShareColors.primaryContainer,
                        iconColor: Colors.white,
                        title: 'Set on map',
                        subtitle: 'Pick a location visually',
                        onTap: () => _openMapPicker(),
                      ),
                    if (!_isSaveMode) ...[
                      const SizedBox(height: 24),
                      _RecentDestinationsSection(
                        onPlaceSelected: _selectPlace,
                        onClear: _clearRecentPlaces,
                      ),
                      const SizedBox(height: 24),
                      _LocationPreviewCard(
                        onRecenter: () => _openMapPicker(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String url;

  const _ProfileAvatar({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: RideShareColors.outlineVariant),
        image: url.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(url),
                fit: BoxFit.cover,
              )
            : null,
        color: RideShareColors.primarySoft,
      ),
      child: url.isEmpty
          ? const Icon(Icons.person, color: RideShareColors.primary, size: 22)
          : null,
    );
  }
}

class _SearchInput extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<Place> onPlaceSelected;
  final String? confirmLabel;

  const _SearchInput({
    required this.controller,
    required this.focusNode,
    required this.onPlaceSelected,
    this.confirmLabel,
  });

  @override
  ConsumerState<_SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends ConsumerState<_SearchInput> {
  String _searchQuery = '';
  bool _isFocused = false;
  String? _loadingPlaceId;

  Future<void> _pickPrediction(dynamic prediction) async {
    setState(() => _loadingPlaceId = prediction.placeId);
    try {
      final placeDetails = await ref.read(
        placeDetailsProvider(prediction.placeId).future,
      );
      final geometry = placeDetails['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      if (location != null && mounted) {
        widget.onPlaceSelected(
          Place(
            id: prediction.placeId,
            name: prediction.mainText,
            address: prediction.fullText,
            latitude: (location['lat'] as num?)?.toDouble() ?? 0,
            longitude: (location['lng'] as num?)?.toDouble() ?? 0,
            type: PlaceType.RECENT,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPlaceId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchResults =
        ref.watch(serpapiPlacesAutocompleteProvider(_searchQuery));
    final bookmarked = ref.watch(bookmarkedPlacesProvider);

    return Column(
      children: [
        Focus(
          onFocusChange: (focused) => setState(() => _isFocused = focused),
          child: AnimatedScale(
            scale: _isFocused ? 1.01 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: RideShareColors.surfaceContainerLow,
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
                  const SizedBox(width: 16),
                  const Icon(Icons.search, color: RideShareColors.primary),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      decoration: const InputDecoration(
                        hintText: 'Where to?',
                        hintStyle: TextStyle(
                          color: RideShareColors.onSurfaceVariant,
                          fontSize: 18,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: RideShareColors.titleText,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: RideShareColors.onSurfaceVariant,
                      onPressed: () {
                        widget.controller.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_searchQuery.length >= 4)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 320),
            decoration: BoxDecoration(
              color: RideShareColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: RideShareColors.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: searchResults.when(
              data: (predictions) {
                if (predictions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No results found'),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: predictions.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color:
                        RideShareColors.outlineVariant.withValues(alpha: 0.5),
                  ),
                  itemBuilder: (context, index) {
                    final prediction = predictions[index];
                    final isLoading = _loadingPlaceId == prediction.placeId;
                    final isSaved =
                        bookmarked.any((p) => p.id == prediction.placeId);
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: RideShareColors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                        child: isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    RideShareColors.primary,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.location_on_outlined,
                                color: RideShareColors.primary,
                                size: 20,
                              ),
                      ),
                      title: Text(
                        prediction.mainText,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        prediction.secondaryText.isNotEmpty
                            ? prediction.secondaryText
                            : prediction.fullText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: RideShareColors.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          isSaved ? Icons.star : Icons.star_border,
                          color: RideShareColors.primary,
                        ),
                        onPressed: () async {
                          final details = await ref.read(
                            placeDetailsProvider(prediction.placeId).future,
                          );
                          final geometry =
                              details['geometry'] as Map<String, dynamic>?;
                          final location =
                              geometry?['location'] as Map<String, dynamic>?;
                          if (location == null) return;
                          await BookmarkedPlacesManager.toggleFavorite(
                            ref,
                            Place(
                              id: prediction.placeId,
                              name: prediction.mainText,
                              address: prediction.fullText,
                              latitude:
                                  (location['lat'] as num?)?.toDouble() ?? 0,
                              longitude:
                                  (location['lng'] as num?)?.toDouble() ?? 0,
                              type: PlaceType.FAVORITE,
                            ),
                          );
                        },
                      ),
                      onTap: isLoading ? null : () => _pickPrediction(prediction),
                    );
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(RideShareColors.primary),
                  ),
                ),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Could not search locations'),
              ),
            ),
          ),
      ],
    );
  }
}

class _ShortcutsSection extends ConsumerWidget {
  final ValueChanged<Place> onPlaceSelected;
  final VoidCallback onSetOnMap;
  final VoidCallback onSetHome;
  final VoidCallback onSetWork;

  const _ShortcutsSection({
    required this.onPlaceSelected,
    required this.onSetOnMap,
    required this.onSetHome,
    required this.onSetWork,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarked = ref.watch(bookmarkedPlacesProvider);
    Place? home;
    Place? work;
    for (final p in bookmarked) {
      if (p.type == PlaceType.HOME && home == null) home = p;
      if (p.type == PlaceType.WORK && work == null) work = p;
    }

    return Column(
      children: [
        _ShortcutTile(
          icon: Icons.map,
          iconBg: RideShareColors.primaryContainer,
          iconColor: Colors.white,
          title: 'Set on map',
          subtitle: 'Pick a location visually',
          onTap: onSetOnMap,
        ),
        const SizedBox(height: 12),
        if (home != null) ...[
          _ShortcutTile(
            icon: Icons.home,
            iconBg: RideShareColors.primarySoft,
            iconColor: RideShareColors.primary,
            title: 'Home',
            subtitle: home.address,
            onTap: () => onPlaceSelected(home!),
            onLongPress: onSetHome,
          ),
        ] else
          _ShortcutTile(
            icon: Icons.home_outlined,
            iconBg: RideShareColors.primarySoft,
            iconColor: RideShareColors.primary,
            title: 'Home',
            subtitle: 'Add your home address',
            onTap: onSetHome,
          ),
        const SizedBox(height: 12),
        if (work != null) ...[
          _ShortcutTile(
            icon: Icons.work,
            iconBg: RideShareColors.primarySoft,
            iconColor: RideShareColors.primary,
            title: 'Work',
            subtitle: work.address,
            onTap: () => onPlaceSelected(work!),
            onLongPress: onSetWork,
          ),
        ] else
          _ShortcutTile(
            icon: Icons.work_outline,
            iconBg: RideShareColors.primarySoft,
            iconColor: RideShareColors.primary,
            title: 'Work',
            subtitle: 'Add your work address',
            onTap: onSetWork,
          ),
        ...bookmarked
            .where((p) =>
                p.type == PlaceType.FAVORITE ||
                (p.type != PlaceType.HOME && p.type != PlaceType.WORK))
            .take(5)
            .map(
              (place) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _ShortcutTile(
                  icon: Icons.star,
                  iconBg: RideShareColors.primarySoft,
                  iconColor: RideShareColors.primary,
                  title: place.name,
                  subtitle: place.address,
                  onTap: () => onPlaceSelected(place),
                ),
              ),
            ),
      ],
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ShortcutTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
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
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
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
              const Icon(Icons.chevron_right, color: RideShareColors.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentDestinationsSection extends ConsumerWidget {
  final ValueChanged<Place> onPlaceSelected;
  final VoidCallback onClear;

  const _RecentDestinationsSection({
    required this.onPlaceSelected,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentPlaces = ref.watch(recentPlacesProvider);
    final bookmarked = ref.watch(bookmarkedPlacesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Destinations',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: RideShareColors.titleText,
              ),
            ),
            if (recentPlaces.isNotEmpty)
              TextButton(
                onPressed: onClear,
                child: const Text(
                  'Clear',
                  style: TextStyle(
                    color: RideShareColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (recentPlaces.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: RideShareColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: RideShareColors.outlineVariant),
            ),
            child: const Text(
              'No recent searches yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: RideShareColors.onSurfaceVariant),
            ),
          )
        else
          ...recentPlaces.map((place) {
            final isSaved = place.isBookmarked ||
                bookmarked.any((b) => b.id == place.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RecentPlaceTile(
                place: place.copyWith(isBookmarked: isSaved),
                onTap: () => onPlaceSelected(place),
                onToggleStar: () =>
                    BookmarkedPlacesManager.toggleFavorite(ref, place),
              ),
            );
          }),
      ],
    );
  }
}

class _RecentPlaceTile extends StatelessWidget {
  final Place place;
  final VoidCallback onTap;
  final VoidCallback onToggleStar;

  const _RecentPlaceTile({
    required this.place,
    required this.onTap,
    required this.onToggleStar,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RideShareColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
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
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: RideShareColors.surfaceContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.history,
                  color: RideShareColors.onSurfaceVariant,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: RideShareColors.titleText,
                      ),
                    ),
                    Text(
                      place.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: RideShareColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onToggleStar,
                icon: Icon(
                  place.isBookmarked ? Icons.star : Icons.star_border,
                  color: RideShareColors.primary,
                  size: 22,
                ),
              ),
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  backgroundColor: RideShareColors.primarySoft,
                  foregroundColor: RideShareColors.primaryDeep,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Book',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationPreviewCard extends ConsumerWidget {
  final VoidCallback onRecenter;

  const _LocationPreviewCard({required this.onRecenter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pickupAsync = ref.watch(pickupDisplayProvider);
    final locationLabel = pickupAsync.maybeWhen(
      data: (p) => p.userName,
      orElse: () => 'Current Location',
    );
    final address = pickupAsync.maybeWhen(
      data: (p) => p.address,
      orElse: () => 'Detecting location…',
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 180,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    RideShareColors.primarySoft,
                    RideShareColors.primary.withValues(alpha: 0.3),
                  ],
                ),
              ),
              child: Icon(
                Icons.map_outlined,
                size: 64,
                color: RideShareColors.primary.withValues(alpha: 0.25),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    RideShareColors.primaryContainer.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Current Location',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        Text(
                          locationLabel,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: onRecenter,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: RideShareColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
